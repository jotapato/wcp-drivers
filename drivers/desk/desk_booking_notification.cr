require "placeos-driver/interface/mailer"
require "./models"

class DeskBookingNotification < PlaceOS::Driver
  descriptive_name "Desk Booking Notification"
  generic_name :DeskBookingNotification
  description %(sends booking notification emails)

  default_settings({
    timezone:         "Australia/Brisbane",
    # https://crystal-lang.org/api/latest/Time/Format.html
    date_time_format: "%c",
    time_format:      "%l:%M%p",
    date_format:      "%A, %-d %B",
    booking_type:     "desk",
    buildings:        "",
  })

  # Ensures these variables are not nilable
  @time_zone : Time::Location = Time::Location.load("Australia/Brisbane")
  @date_time_format : String = "%c"
  @time_format : String = "%l:%M%p"
  @date_format : String = "%A, %-d %B"
  @booking_type : String = "desk"
  @buildings : Array(String) = [] of String

  def on_update
    # Update the instance variables based on the settings
    time_zone = setting?(String, :calendar_time_zone).presence || "Australia/Brisbane"
    @time_zone = Time::Location.load(time_zone)
    @date_time_format = setting?(String, :date_time_format) || "%c"
    @time_format = setting?(String, :time_format) || "%l:%M%p"
    @date_format = setting?(String, :date_format) || "%A, %-d %B"
    @booking_type = setting?(String, :booking_type).presence || "desk"
    @buildings = setting?(Array(String), :buildings) || [] of String

    # Configure any schedules here
    # https://github.com/spider-gazelle/tasker
    # schedule.clear
    # schedule.every(5.minutes) { poll_bookings }
    # schedule.cron("30 7 * * *", @time_zone) { poll_bookings }
  end

  def on_load
    # Some form of asset booking has occurred (such as a desk booking)
    monitor("staff/booking/changed") { |_subscription, payload| check_booking(payload) }

    on_update
  end

  # Get a reference to the module to be used to send emails
  def mailer
    system.implementing(Interface::Mailer)
  end

  # Access another module in the system
  accessor staff_api : StaffAPI_1

  protected def check_booking(payload : String)
    logger.debug { "received booking event payload: #{payload}" }
    booking_details = Booking.from_json payload
    process_booking(booking_details)
  end

  # Ensure we don't have two fibers processing this at once
  # (technically the driver is thread safe, but it is concurrent)
  @check_bookings_mutex = Mutex.new

  @[Security(Level::Support)]
  def poll_bookings(months_from_now : Int32 = 2)
    # Clean up old debounce data
    expired = 5.minutes.ago.to_unix
    @debounce.reject! { |_, (_event, entered)| expired > entered }

    now = Time.utc.to_unix
    later = months_from_now.months.from_now.to_unix

    @check_bookings_mutex.synchronize do
      @buildings.each do |building_zone|
        # bookings that haven't been approved
        bookings = staff_api.query_bookings(
          type: @booking_type,
          period_start: now,
          period_end: later,
          zones: [building_zone],
          approved: false,
          rejected: false,
          created_before: 2.minutes.ago.to_unix
        ).get.as_a

        # bookings that have been approved
        bookings = bookings + staff_api.query_bookings(
          type: @booking_type,
          period_start: now,
          period_end: later,
          zones: [building_zone],
          approved: true,
          rejected: false,
          created_before: 2.minutes.ago.to_unix
        ).get.as_a

        # Convert to nice objects
        bookings = Array(Booking).from_json(bookings.to_json)

        logger.debug { "checking #{bookings.size} requested bookings in #{building_zone}" }
        bookings.each { |booking_details| process_booking(booking_details) }
      end
    end
  end

  # Booking id => event action, timestamp
  @debounce = {} of Int64 => {String?, Int64}
  @bookings_checked = 0_u64

  protected def process_booking(booking_details : Booking)
    # Ignore when a bookings state is updated
    return if {"process_state", "metadata_changed"}.includes?(booking_details.action)

    # Ignore the same event in a short period of time
    previous = @debounce[booking_details.id]?
    return if previous && previous[0] == booking_details.action
    @debounce[booking_details.id] = {booking_details.action, Time.utc.to_unix}

    # Set the correct time given the timezone, if different from the default
    timezone = booking_details.timezone.presence || @time_zone.name
    location = Time::Location.load(timezone)

    # Set the date and time forme like: Tue Apr 15 10:26:19 2021
    starting = Time.unix(booking_details.booking_start).in(location)
    ending = Time.unix(booking_details.booking_end).in(location)

    # Ignore changes to bookings that have already ended
    return if Time.utc > ending

    building_zone, building_name = get_building_details(booking_details.zones)

    # Set keys values to be used when sending emails
    args = {
      booking_id:     booking_details.id,
      start_time:     starting.to_s(@time_format),
      start_date:     starting.to_s(@date_format),
      start_datetime: starting.to_s(@date_time_format),
      end_time:       ending.to_s(@time_format),
      end_date:       ending.to_s(@date_format),
      end_datetime:   ending.to_s(@date_time_format),
      starting_unix:  booking_details.booking_start,

      desk_id:    booking_details.asset_id,
      user_id:    booking_details.user_id,
      user_email: booking_details.user_email,
      user_name:  booking_details.user_name,
      reason:     booking_details.title,

      level_zone:    booking_details.zones.reject { |z| z == building_zone }.first?,
      building_zone: building_zone,
      building_name: building_name,
      support_email: support_email,

      approver_name:  booking_details.approver_name,
      approver_email: booking_details.approver_email,

      booked_by_name:  booking_details.booked_by_name,
      booked_by_email: booking_details.booked_by_email,
    }

    # Send email logic depending on the booking action step
    case booking_details.action
      when "approved"
        mailer.send_template(
          to: booking_details.user_email,
          template: {"bookings", "booking_approved"},
          args: args
        )

        staff_api.booking_state(booking_details.id, "approval_sent").get
    end

    # nice to see some status in backoffice
    @bookings_checked += 1
    self[:bookings_checked] = @bookings_checked
  end

  # id => tags, name
  @zone_cache = {} of String => Tuple(Array(String), String)

  def get_building_details(zones : Array(String))
    zones.each do |zone_id|
      zone_info = @zone_cache[zone_id]? || get_zone(zone_id)
      next unless zone_info
      next unless zone_info[0].includes?("building")

      return {zone_id, zone_info[1]}
    end

    nil
  end

  def get_zone(zone_id : String)
    zone = staff_api.zone(zone_id).get
    tags = zone["tags"].as_a.map(&.as_s)
    name = zone["name"].as_s
    tuple = {tags, name}
    @zone_cache[zone_id] = tuple
    tuple
  rescue error
    logger.warn(exception: error) { "error obtaining zone details for #{zone_id}" }
    nil
  end
end

require "placeos-driver/interface/mailer"

class StaffAPI < DriverSpecs::MockDriver
  # Mock the StaffAPI user data for this test
  def query_bookings(
    type : String,
    period_start : Int64? = nil,
    period_end : Int64? = nil,
    zones : Array(String) = [] of String,
    user : String? = nil,
    email : String? = nil,
    state : String? = nil,
    created_before : Int64? = nil,
    created_after : Int64? = nil,
    approved : Bool? = nil,
    rejected : Bool? = nil
  )
    logger.info { "Querying desk bookings!" }

    now = Time.local
    start = now.at_beginning_of_day.to_unix
    ending = now.at_end_of_day.to_unix

    [{
      id:            1,
      booking_type:  type,
      booking_start: start,
      booking_end:   ending,
      asset_id:      "desk-123",
      user_id:       "user-1234",
      user_email:    "jane.doe@test.com",
      user_name:     "Jane Doe",
      zones:         ["zone-123"],
      checked_in:    false,
      rejected:      false,
    },
    {
      id:            2,
      booking_type:  type,
      booking_start: start,
      booking_end:   ending,
      asset_id:      "desk-456",
      user_id:       "user-456",
      user_email:    "zee.doo@test.com",
      user_name:     "Zee Doo",
      zones:         ["zone-456"],
      checked_in:    false,
      rejected:      false,
    }]
  end

  def zone(zone_id : String)
    logger.info { "requesting zone: #{zone_id}" }
    if zone_id == "zone-123"
      {
        "id"   => zone_id,
        "name" => zone_id,
        "tags" => ["level"],
      }
    else
      {
        "id"   => zone_id,
        "name" => zone_id,
        "tags": ["building"],
      }
    end
  end

  def booking_state(booking_id : String | Int64, state : String)
    logger.info { "updating booking id \"#{booking_id}\" state to: #{state}" }
    true
  end
end

class SMTP < DriverSpecs::MockDriver
  # Mock the SMTP email data for this test
  include PlaceOS::Driver::Interface::Mailer

  def send_mail(
    to : String | Array(String),
    subject : String,
    message_plaintext : String? = nil,
    message_html : String? = nil,
    resource_attachments : Array(ResourceAttachment) = [] of ResourceAttachment,
    attachments : Array(Attachment) = [] of Attachment,
    cc : String | Array(String) = [] of String,
    bcc : String | Array(String) = [] of String,
    from : String | Array(String) | Nil = nil
  )
    logger.info { "email sent" }
    self[:message] = message_html
  end

  def send_template(
    to : String | Array(String),
    template : Tuple(String, String),
    args : TemplateItems,
    resource_attachments : Array(ResourceAttachment) = [] of ResourceAttachment,
    attachments : Array(Attachment) = [] of Attachment,
    cc : String | Array(String) = [] of String,
    bcc : String | Array(String) = [] of String,
    from : String | Array(String) | Nil = nil
  )
    logger.info { "sending email template to: #{to}" }
    self[:email_template] = template
    self[:to_email] = to
  end
end

DriverSpecs.mock_driver "Desk::DeskBookingNotification" do
  system({
    StaffAPI: {StaffAPI},
    Mailer:   {SMTP},
  })

  now = Time.local
  start = now.at_beginning_of_day.to_unix
  ending = now.at_end_of_day.to_unix

  # Mock payload call data
  payload = {
    action:          "changed",
    id:              1,
    booking_type:    "desk",
    booking_start:   start,
    booking_end:     ending,
    asset_id:        "desk-123",
    user_id:         "user-1234",
    user_email:      "jane.doe@test.com",
    user_name:       "Jane Doe",
    zones:           ["zone-123"],
    booked_by_name:  "Jhon Doe",
    booked_by_email: "jhon.doe@test.com",
  }

  # Execute commandand wait until finish so then the system can check the result
  exec(:check_booking, payload.to_json).get
  # Expect the email message text to be the correct one
  system(:Mailer_1)[:message] = "message_html"
  system(:Mailer_1)[:message].should eq("message_html")
  # Expect the email template from the payload action: changed
  system(:Mailer_1)[:email_template].should eq(["bookings", "booking_notification"])
  # Expect to send the email to the user, instead of the booked by user
  system(:Mailer_1)[:to_email].should eq(payload["user_email"])
end

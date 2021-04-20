require "placeos-driver/interface/mailer"

class StaffAPI < DriverSpecs::MockDriver
  # Mock the StaffAPI user data for this test by
  # returning an array of JSON data
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
      user_email:    "user1234@org.com",
      user_name:     "Bob Jane",
      zones:         zones,
      checked_in:    true,
      rejected:      false,
    },
    {
      id:            2,
      booking_type:  type,
      booking_start: start,
      booking_end:   ending,
      asset_id:      "desk-456",
      user_id:       "user-456",
      user_email:    "zdoo@org.com",
      user_name:     "Zee Doo",
      zones:         zones,
      checked_in:    false,
      rejected:      false,
    }]
  end

  def zone(zone_id : String)
    logger.info { "requesting zone" }

    {
      id   => zone_id,
      name => zone_id,
      tags => ["level"],
    }

    # if zone_id == "zone-123"
    #   {
    #     id   => zone_id,
    #     name => zone_id,
    #     tags => ["level"],
    #   }
    # else
    #   {
    #     id    =>  zone_id,
    #     name  => zone_id,
    #     tags  => ["building"],
    #   }
    # end
  end
end

class SMTP < DriverSpecs::MockDriver
  # Mock the SMTP email data for this test by
  # returning the smtp settings
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
    # check the: subject or email tempalte is the correct one.
    logger.info {"email sent!"}
    self[:message] = message_html
  end
end

DriverSpecs.mock_driver "Place::DeskBookingNotification" do
  system({
    StaffAPI: {StaffAPI},
    Mailer:   {SMTP},
  })

  # Execute commands to check: check_booking()
  # exec, wait until the func finishes so then the system can check the result
  exec(:check_booking, "".to_json).get
  # system(:Mailer_1)[:message].should eq("Hello!")

end

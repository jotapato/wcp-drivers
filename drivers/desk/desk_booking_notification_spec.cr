DriverSpecs.mock_driver "Desk::DeskBookingNotification" do
  system({
    StaffAPI: {StaffAPI},
  })

  settings({
    timezone:         "Australia/Brisbane",
    date_time_format: "%c",
    time_format:      "%l:%M%p",
    date_format:      "%A, %-d %B",
    booking_type:     "desk",
    buildings:        "",
  })


end

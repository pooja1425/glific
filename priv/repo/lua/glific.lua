--
-- The main glific lua interface with a bunch of helper functions
-- and commonly used functions across multiple organizations
--
-- The first set of functions will include the ability to get contact and
-- flow specific data so we can use those data points to decide on future
-- actions
--
-- Our first sample use cases will be to try and script
--   * STiR Survey
--   * Ability to set a trigger for a specific time and frequency for a contact
--

--[[
  Here is a sample map that glific adds to the lua state

  %{
    contact: %{
      fields: %{
        "age_group" => %{
          "inserted_at" => "2021-01-27T21:51:07.771603Z",
          "label" => "Age Group",
          "type" => "string",
          "value" => "11 to 14"
        },
        "name" => %{
          "inserted_at" => "2021-01-27T21:51:02.832491Z",
          "label" => "Name",
          "type" => "string",
          "value" => "lobo"
        }
      },
      name: "Donald Lobo",
      phone: "14156139297"
    },
    results: %{
      "A1" => %{"category" => "Y", "input" => "y"},
      "A2" => %{"category" => "N", "input" => "n"},
      "A3" => %{"category" => "Y", "input" => "y"},
      "A4" => %{"category" => "N", "input" => "n"},
      "A5" => %{"category" => "Y", "input" => "y"},
      "A6" => %{"category" => "Y", "input" => "y"}
    }
  }
]]

function survey_webhook(contact, flow_results, staff)

end

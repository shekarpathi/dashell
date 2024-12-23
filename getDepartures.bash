#!/bin/bash
clear
clear
# Define constants
user_agent="Mozilla/5.0 Gecko/20100101 Firefox/133.0"
accept_language="en-US,en;q=0.5"
accept_encoding="gzip, deflate, br"
token_url="https://www.united.com/api/auth/anonymous-token"

# URL to fetch the JSON data
URL="https://www.flydulles.com/arrivals-and-departures/json"
curl -s "$URL" | jq | wc -l
curl -s "$URL" | jq [.departures[]] > departures_raw.json
curl -s "$URL" | jq [.arrivals[]] > arrivals_raw.json
exit 0
# Output file
#DEPARTURES_HTML="departures.html"

# Output file
DEPARTURES_FILE="departures.json"

# Get today's date in the expected format (e.g., "2024-12-18")
TODAY=$(date '+%Y-%m-%d')

# Current timestamp in seconds since epoch
NOW=$(date '+%s')

# Function to get a new token hash
get_new_hash() {
  response=$(curl -s -X GET "$token_url" \
    -H "User-Agent: $user_agent" \
    -H "Accept-Language: $accept_language" \
    -H "Accept-Encoding: $accept_encoding")
  echo "$response" | jq -r '.data.token.hash'
}

# Function to fetch flight response
get_flight_status() {
  curl -s -X GET "$2" \
    -H "User-Agent: $user_agent" \
    -H "X-Authorization-Api: $1"
}

get_boardtime_string() {
  # Step 2: Attempt to fetch flight status
  flight_response=$(get_flight_status "$hash" "$1")

  echo "$flight_response" | jq -r '
    .data.flightLegs[0].OperationalFlightSegments[0] |
    {
      BoardTime: (.BoardTime | split(":")[:2] | join(":")),
      "Boarding Start Time": ((.Characteristic[] | select(.Code == "LocalEstimatedBoardStartDateTime") | .Value) | split("T")[1] | split(":")[:2] | join(":")),
      "Boarding End Time": ((.Characteristic[] | select(.Code == "LocalEstimatedBoardEndDateTime") | .Value) | split("T")[1] | split(":")[:2] | join(":"))
    }|
    "BT \( .BoardTime )\nST \( .["Boarding Start Time"] )\nET \( .["Boarding End Time"] )"
    '
}

# shellcheck disable=SC2155
export hash=$(get_new_hash)
echo "$hash"

# Fetch the JSON data, filter for today's publishedTime, compute correct_time, remove the "id" field, and write to the output file
DEPARTURES_JSON=$(curl -s "$URL" | jq --arg today "$TODAY" --argjson now "$NOW" '
  [.departures[]
  | select((.publishedTime | startswith($today)) and .dep_airport_code == "IAD")
  | .departure_time = (if .actualtime then .actualtime else .publishedTime end)
  | .gate = (if .mod_gate then .mod_gate else .gate end)
  | .codeshared_flights = (
      [.codeshare[]
       | (.IATA + .flightnumber)
      ] | join(", ")
    )
  | .boardURL = ("https://www.united.com/api/flight/status/" + .flightnumber + "/" + "2024-12-22" +  "?carrierCode=" + .IATA)
  | .flight = (.IATA + " " + .flightnumber)
  | .airport = (.airportcode + " " + .city)
  | del(.IATA, .flightnumber, .airportcode, .city, .mod_gate, .id, .mwaaTime, .baggage, .publishedTime, .actualtime, 
        .aircraftInfo, .arr_terminal, .arr_gate, .departureInfo, .mod_status, .codeshare, .dep_airport_code, .dep_terminal, .international)
  ]
  | sort_by(.departure_time)
')

ls -ltra $DEPARTURES_FILE

# Check if the operation was successful and if the file has content
if [ -s "$DEPARTURES_FILE" ]; then
  echo "Departures with today's publishedTime, computed correct_time, and no 'id' field have been written to $DEPARTURES_FILE"
else
  echo "No departures found with publishedTime matching today's date ($TODAY)."
  # Optionally remove the empty file
  rm -f "$DEPARTURES_FILE"
  exit 1
fi

echo "$DEPARTURES_JSON" | jq '[.[] | {flight: .flight, airport: .airport, airline: .airline, gate: .gate, departure_time: .departure_time, status: .status, codeshared_flights: .codeshared_flights, board_URL: .boardURL}]' > $DEPARTURES_FILE

#cat $DEPARTURES_FILE

# Create an empty array for the updated JSON
updated_json="[]"

# Iterate through each item in the JSON
updated_json=$(jq -c '.[]' "$DEPARTURES_FILE" | while read -r item; do
  # Extract the board_URL
  board_url=$(echo "$item" | jq -r '.board_URL')

  # Make an HTTPS request and capture the response code
  #response_code=$(curl -s -o /dev/null -w "%{http_code}" "$board_url")
  boarding_time=$(get_boardtime_string "$board_url")

  # Add the response_code field to the JSON object
  updated_item=$(echo "$item" | jq --arg rc "$boarding_time" '. + {boarding_time: $rc}')

  # Output the updated item
  echo "$updated_item"
done | jq -s '.')

echo "$updated_json" > $DEPARTURES_FILE

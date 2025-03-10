#!/bin/bash

#  git pull --rebase origin main
clear
clear
echo "=========================="
echo "$1 Run Started $NOW"
date
echo "=========================="
# Define constants
user_agent="Mozilla/5.0 Gecko/20100101 Firefox/133.0"
accept_language="en-US,en;q=0.5"
accept_encoding="gzip, deflate, br"
token_url="https://www.united.com/api/auth/anonymous-token"
rm /home/ec2-user/dashell/JJ*.json
# URL to fetch the JSON data
URL="https://www.flydulles.com/arrivals-and-departures/json"
# shellcheck disable=SC2155
export totalLinesInArrDepJson=$(curl -s "$URL" | jq '.' | wc -l)
echo "Total lines in Arrivals Departures json is :$totalLinesInArrDepJson)"
curl -s "$URL" | jq [.departures[]] > departures_raw.json
curl -s "$URL" | jq [.arrivals[]] > arrivals_raw.json
ls -ltra *_raw.json

# Output file
#DEPARTURES_HTML="departures.html"

# Output file
DEPARTURES_STAGE_FILE="departures_stage.json"
DEPARTURES_FILE="departures.json"

# Get today's date in the expected format (e.g., "2024-12-18")
TODAY=$(date '+%Y-%m-%d')

# Current timestamp in seconds since epoch
NOW=$(date '+%s')

# Function to get a new token hash
get_united_bearer_token() {
  response=$(curl -s -X GET "$token_url" \
    -H "User-Agent: $user_agent" \
    -H "Accept-Language: $accept_language" \
    -H "Accept-Encoding: $accept_encoding")
  echo "$response" | jq -r '.data.token.hash'
}

# Function to fetch flight response
get_boardingTime_json() {
  curl -s -X GET "$2" \
    -H "User-Agent: $user_agent" \
    -H "X-Authorization-Api: $1"
}

parse_boardingTimeString_From_Json() {
  # Step 2: Attempt to fetch flight status
  flight_response=$(get_boardingTime_json "$hash" "$1")
  current_time=$(date +"%H%M%S")
  echo "$flight_response" | jq '.' > JJ_FlightResponse_"$current_time".json
  echo "$flight_response" | jq -r '
  .data.flightLegs[]
  | .OperationalFlightSegments[]
  | select(.DepartureAirport.IATACode == "IAD")
  | {
      BoardTime: (.BoardTime | split(":")[:2] | join(":")),
      "Boarding Start Time": ((.Characteristic[] | select(.Code == "LocalEstimatedBoardStartDateTime") | .Value) | split("T")[1] | split(":")[:2] | join(":")),
      "Boarding End Time": ((.Characteristic[] | select(.Code == "LocalEstimatedBoardEndDateTime") | .Value) | split("T")[1] | split(":")[:2] | join(":"))
    } |
    "BT \( .BoardTime )\nST \( .["Boarding Start Time"] )\nET \( .["Boarding End Time"] )"
    '
#    cat PP"$current_time".json
}

add_time_left_for_departure() {
  # $1 contains YYYY-MM-DD HH:MM:SS
  # Get current time in seconds since epoch
  now_seconds=$(date +%s)

  # Convert the given timestamp to seconds since epoch
  timestamp_seconds=$(date -d "$1" +%s)

  # Calculate the difference in seconds
  diff_seconds=$((timestamp_seconds - now_seconds))

  # Determine the sign (positive for future, negative for past)
  if [ $diff_seconds -ge 0 ]; then
      sign="+"
  else
      sign="-"
      diff_seconds=$((diff_seconds * -1)) # Convert to positive for formatting
  fi

  # Convert seconds to HH:MM format
  hours=$((diff_seconds / 3600))
  minutes=$(((diff_seconds % 3600) / 60))

  # Format with leading zeros and prepend the sign
  printf "%s%02d:%02d\n" "$sign" "$hours" "$minutes"
}

# shellcheck disable=SC2155
export hash=$(get_united_bearer_token)
#echo "$hash"


# Main logic
retry_count=0
# Maximum number of retries
max_retries=8
# Delay between retries in seconds
delay=15

while true; do
  response=$(curl -s -w "%{http_code}" "$URL" | jq '.')
  http_code=$(tail -n1 <<< "$response")  # get the last line
#  echo $http_code
  if [[ $http_code -lt 300 ]]; then
      content=$(sed '$ d' <<< "$response")   # get all but the last line which contains the status code
      break
  else
    echo "Error: HTTP code $http_code."
    retry_count=$((retry_count + 1))
    if [[ $retry_count -ge $max_retries ]]; then
        echo "Error: HTTP code $http_code after $retry_count retries. Exiting."
        exit 1
    fi
    echo "HTTP code $http_code. Retrying in $delay seconds..."
    sleep $delay
  fi
done
#echo "$content"
#exit 0

# Fetch the JSON data, filter for today's publishedTime, compute correct_time, remove the "id" field, and write to the output file
DEPARTURES_JSON=$(echo "$content" | jq --arg today "$TODAY" --argjson now "$NOW" '
  [.departures[]
  | select((.publishedTime | startswith($today)) and .dep_airport_code == "IAD")
  | .departure_time = ((if .actualtime then .actualtime else .publishedTime end))
  | .departure_time_hh_mm = ((if .actualtime then .actualtime else .publishedTime end) | split(" ")[1] | split(":")[0:2] | join(":"))
  | .gate = (if .mod_gate then .mod_gate else .gate end)
  | .codeshared_flights = (
      [.codeshare[]
       | (.IATA + .flightnumber)
      ] | join(", ")
    )
  | .boardURL = ("https://www.united.com/api/flight/status/" + .flightnumber + "/" + $today +  "?carrierCode=" + .IATA)
  | .flight = (.IATA + .flightnumber)
  | .airline_code = (.IATA)
  | .airport = (.airportcode + " " + .city)
  | del(.IATA, .flightnumber, .airportcode, .city, .mod_gate, .id, .mwaaTime, .baggage, .publishedTime, .actualtime,
        .aircraftInfo, .arr_terminal, .arr_gate, .departureInfo, .mod_status, .codeshare, .dep_airport_code, .dep_terminal, .international)
  ]
  | sort_by(.departure_time)
')

echo "$DEPARTURES_JSON" > departures_raw_filtered.json
ls -ltra departures_raw_filtered.json

echo "$DEPARTURES_JSON" | jq '[.[] | {flight: .flight, airport: .airport, airline: .airline, gate: .gate, departure_time: .departure_time, departure_time_hh_mm: .departure_time_hh_mm, status: .status, codeshared_flights: .codeshared_flights, board_URL: .boardURL, airline_code: .airline_code}]' > $DEPARTURES_STAGE_FILE

# Check if the operation was successful and if the file has content
if [ -s "$DEPARTURES_STAGE_FILE" ]; then
  echo "Departures written to $DEPARTURES_STAGE_FILE"
  ls -ltra $DEPARTURES_STAGE_FILE
  echo "Now going to populate the boarding start and end times"
else
  echo "No departures found with publishedTime matching today's date ($TODAY)."
  # Optionally remove the empty file
  rm -f "$DEPARTURES_STAGE_FILE"
  rm -f JJ*.json
  exit 0
fi

TEMP=$(cat "$DEPARTURES_STAGE_FILE" | jq '.')
#echo $TEMP | jq '.'
# Process JSON and update the timeDelta field
UPDATED_JSON=$(echo "$TEMP" | jq -c '.[]' | while read -r row; do
    departure_time=$(echo "$row" | jq -r '.departure_time')
    now_seconds=$(date +%s)
    # Determine the OS
    os_type=$(uname)
    if [[ "$os_type" == "Linux" ]]; then
      timestamp_seconds=$(date -d "$departure_time" +%s)
    elif [[ "$os_type" == "Darwin" ]]; then
      timestamp_seconds=$(date -j -f "%Y-%m-%d %H:%M:%S" "$departure_time" +%s)
    elif [[ "$os_type" == "CYGWIN"* || "$os_type" == "MINGW"* ]]; then
      timestamp_seconds=0
    else
      timestamp_seconds=0
#      echo "Unknown operating system: $os_type"
    fi
    diff_seconds=$((timestamp_seconds - now_seconds))
    if [ $diff_seconds -ge 0 ]; then
        sign="+"
    else
        sign="-"
        diff_seconds=$((diff_seconds * -1)) # Convert to positive for formatting
    fi
    hours=$((diff_seconds / 3600))
    minutes=$(((diff_seconds % 3600) / 60))
    #printf "%s%02d:%02d\n" "$sign" "$hours" "$minutes"
    time_delta=$(printf "%s%02d:%02d\n" "$sign" "$hours" "$minutes")

    echo "$row" | jq --arg timeDelta "$time_delta" '.timeDelta = $timeDelta'
done | jq -s '.')
#echo $UPDATED_JSON
echo $UPDATED_JSON | jq '.' > $DEPARTURES_STAGE_FILE

#cat $DEPARTURES_STAGE_FILE
ls -ltra $DEPARTURES_STAGE_FILE
#exit 0

# Create an empty array for the updated JSON
updated_json="[]"

# Iterate through each item in the JSON
updated_json=$(jq -c '.[]' "$DEPARTURES_STAGE_FILE" | while read -r item; do
  # Extract the board_URL
  board_url=$(echo "$item" | jq -r '.board_URL')
  airline_code=$(echo "$item" | jq -r '.airline_code')

  if [[ "$airline_code" == "UA" ]]; then
    # Make an HTTPS request and capture the response code
    #response_code=$(curl -s -o /dev/null -w "%{http_code}" "$board_url")
    boarding_time=$(parse_boardingTimeString_From_Json "$board_url")
  else
    boarding_time=""
  fi

  # Add the response_code field to the JSON object
#  updated_item=$(echo "$item" | jq --arg rc "$boarding_time" '. + {boarding_time: $rc}  | del(.board_URL)')
  updated_item=$(echo "$item" | jq --arg rc "$boarding_time" '. + {boarding_time: $rc}')

  # Output the updated item
  echo "$updated_item"
done | jq -s '.')

echo "$updated_json" > $DEPARTURES_STAGE_FILE

ls -ltra "$DEPARTURES_STAGE_FILE" "$DEPARTURES_FILE"
echo "renaming $DEPARTURES_STAGE_FILE to $DEPARTURES_FILE"
mv "$DEPARTURES_STAGE_FILE" "$DEPARTURES_FILE"
ls -ltra "$DEPARTURES_STAGE_FILE" "$DEPARTURES_FILE"
date
echo "=========================="
echo "$1 Run Ended"
date
echo "=========================="

#!/bin/bash

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo ""
    echo "OpenX Reporting API Bash Client"
    echo "--------------------------------"
    echo "This script authenticates with the OpenX Reporting API using OAuth2 ,"
    echo "generates a report, waits until it's ready, and downloads it as CSV."
    echo ""
    echo "Usage:"
    echo "  ./reporting_api_report.sh"
    echo ""
    echo "Configuration:"
    echo "  Edit the script and replace the following placeholders with your credentials:"
    echo "    CLIENT_ID           -> Your OpenX OAuth2 client ID"
    echo "    EMAIL               -> Your OpenX login email"
    echo "    PASSWORD            -> Your OpenX login password"
    echo "    INSTANCE_HOSTNAME   -> Your OpenX instance hostname "
    echo ""
    echo "Dependencies:"
    echo "  - curl"
    echo "  - jq"
    echo "  - openssl"
    echo ""
    echo "Output:"
    echo "  A file named report.csv containing the downloaded report."
    exit 0
fi

# ---- CONFIG ----
CLIENT_ID="<client_id>"
EMAIL="<email>"
PASSWORD="<password>"
INSTANCE_HOSTNAME="<instance_hostname>"

# Note: The GCIP_KEY is a public key and can be found in the OpenX documentation.
GCIP_KEY="AIzaSyCLvqp5phL0yGo0uxIN-l7a58mPkV74hsw"

REDIRECT_URI="https://unity.openx.com/response-oidc"
AUTHORIZE_URL="https://api.openx.com/oauth2/v1/authorize"
SESSION_INFO_URL="https://api.openx.com/oauth2/v1/login/session-info"
CONSENT_URL="https://api.openx.com/oauth2/v1/login/consent"
TOKEN_URL="https://api.openx.com/oauth2/v1/token"
REPORT_GENERATE_URL="https://api.openx.com/api/v1/reporting-api/generateReport"
REPORT_PULL_URL="https://api.openx.com/api/v1/reporting-api/pullReport"

# ---- HELPERS ----

generate_code_verifier() {
    openssl rand -base64 32 | tr -d '=+/[:space:]' | cut -c -43
}

generate_code_challenge() {
    local verifier="$1"
    echo -n "$verifier" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '='
}

extract_query_param() {
    local url="$1"
    local param="$2"
    echo "$url" | sed -n "s/.*[?&]$param=\([^&#]*\).*/\1/p"
}

# ---- STEP 1: Get ID Token ----
get_auth_token() {
    curl -s -X POST "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$GCIP_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"returnSecureToken\":true}"
}

# ---- MAIN ----
main() {
    echo "🔑 Getting ID token..."
    auth_response=$(get_auth_token)
    id_token=$(echo "$auth_response" | jq -r '.idToken')

    if [[ "$id_token" == "null" || -z "$id_token" ]]; then
        echo "❌ Failed to get idToken"
        echo "$auth_response"
        exit 1
    fi

    code_verifier=$(generate_code_verifier)
    code_challenge=$(generate_code_challenge "$code_verifier")

    echo "📡 Authorizing session..."

    # Build the authorize URL correctly with URL-encoded params
    authorize_response=$(curl -s -L -G "$AUTHORIZE_URL" \
        --data-urlencode "scope=openid email profile api" \
        --data-urlencode "response_type=code" \
        --data-urlencode "client_id=$CLIENT_ID" \
        --data-urlencode "redirect_uri=$REDIRECT_URI" \
        --data-urlencode "state=abcd" \
        --data-urlencode "code_challenge=$code_challenge" \
        --data-urlencode "code_challenge_method=S256" \
        --data-urlencode "nonce=nonce-123456" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -w "%{url_effective}" -o /dev/null)

    # Now extract session_id from the final URL
    session_id=$(extract_query_param "$authorize_response" "session_id")

    if [[ -z "$session_id" ]]; then
        echo "❌ Could not extract session_id from authorize URL:"
        echo "$authorize_response"
        exit 1
    fi

    echo "ℹ️ Session ID: $session_id"

    echo "📄 Getting session info..."
    session_info=$(curl -s -G "$SESSION_INFO_URL" \
        --data-urlencode "session_id=$session_id" \
        -H "Authorization: Bearer $id_token" \
        -H "Origin: https://login.openx.com")

    # Verify response isn't empty
    if [[ -z "$session_info" || "$session_info" == "null" ]]; then
        echo "❌ session_info response is empty or invalid:"
        echo "$session_info"
        exit 1
    fi

    echo "session info response: $session_info"

    scope=$(echo "$session_info" | jq -r '.scope // empty')

    if [[ -z "$scope" ]]; then
        echo "❌ Scope not found in session_info"
        echo "$session_info"
        exit 1
    fi

    echo "✅ Session info retrieved, scope: $scope"

    echo "📝 Granting consent..."
    consent_response=$(curl -s -X POST "$CONSENT_URL" \
        -H "Authorization: Bearer $id_token" \
        -H "Origin: https://login.openx.com" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "consent=true" \
        --data-urlencode "scope=$scope" \
        --data-urlencode "session_id=$session_id" \
        --data-urlencode "instance_hostname=$INSTANCE_HOSTNAME")

    code=$(echo "$consent_response" | jq -r '.code')

    echo $consent_response

    echo "🔓 Getting access token..."
    token_response=$(curl -s -X POST "$TOKEN_URL" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=authorization_code" \
        --data-urlencode "code=$code" \
        --data-urlencode "redirect_uri=$REDIRECT_URI" \
        --data-urlencode "client_id=$CLIENT_ID" \
        --data-urlencode "code_verifier=$code_verifier")

    access_token=$(echo "$token_response" | jq -r '.access_token')

    if [[ -z "$access_token" || "$access_token" == "null" ]]; then
        echo "❌ Failed to get access token"
        echo "$token_response"
        exit 1
    fi

    echo "✅ Access token received."

    # ---- GENERATE REPORT ----
    echo "📊 Generating report..."
    report_request='{
        "reportType": "HOURLY",
        "dateFrom": "2025-02-01T00:00:00Z",
        "dateTo": "2025-02-01T01:00:00Z",
        "dimensions": ["hour", "pageDomain"],
        "metrics": ["allRequests", "clicks"]
    }'

    report_response=$(curl -s -X POST "$REPORT_GENERATE_URL" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        -H "Origin: https://unity.openx.com" \
        -d "$report_request")

    report_id=$(echo "$report_response" | jq -r '.id')
    echo "📎 Report ID: $report_id"

    # ---- POLL REPORT ----
    echo "⏳ Waiting for report to be ready..."

    while true; do
        poll_response=$(curl -s -w "%{http_code}" -o report.csv.raw -X POST "$REPORT_PULL_URL" \
            -H "Authorization: Bearer $access_token" \
            -H "Content-Type: application/json" \
            -H "Origin: https://unity.openx.com" \
            -d "{\"id\":\"$report_id\"}")

        if [[ "$poll_response" == "200" ]]; then
            mv report.csv.raw report.csv
            echo "✅ Report downloaded: report.csv"
            break
        elif [[ "$poll_response" == "202" ]]; then
            echo "⌛ Report is still processing. Retrying in 10s..."
            sleep 10
        else
            echo "❌ Unexpected response. HTTP status: $poll_response"
            cat report.csv.raw
            exit 1
        fi
    done
}

main

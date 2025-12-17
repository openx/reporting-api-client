import requests
import time

from reporting_api_auth_client import AuthClient

generate_report_parameters = {
    "reportType": "HOURLY",
    "dateFrom": "2025-06-01T00:00:00Z",
    "dateTo": "2025-06-01T01:00:00Z",
    "dimensions": ["Hour", "PageDomain"],
    "metrics": ["AllRequests"]
}

# Constants
REPORT_GENERATE_URL = "https://api.openx.com/api/v1/reporting-api/generateReport"
REPORT_PULL_URL = "https://api.openx.com/api/v1/reporting-api/pullReport"

# Function to generate a report
def generate_report(token):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Origin": "https://unity.openx.com"
    }

    response = requests.post(REPORT_GENERATE_URL, json=generate_report_parameters, headers=headers)
    response.raise_for_status()
    return response.json()["id"]

# Function to poll for report readiness
def wait_for_report(token, report_id):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Origin": "https://unity.openx.com"
    }
    payload = {"id": report_id}

    while True:
        response = requests.post(REPORT_PULL_URL, json=payload, headers=headers)

        if response.status_code == 200:
            return response.content  # CSV content
        elif response.status_code == 202:
            print("Report generation in progress. Retrying in 10 seconds...")
            time.sleep(10)
        else:
            response.raise_for_status()

# Main process
if __name__ == "__main__":
    try:
        client = AuthClient(
            client_id="<client_id>",
            email="<email>",
            password="<password>",
            hostname="<hostname>"
        )
        token = client.get_token()
        print(f"OAuth token obtained; {token}")

        report_id = generate_report(token)
        print(f"Report generated with ID: {report_id}")

        csv_data = wait_for_report(token, report_id)
        print("Report is ready. Saving to file...")

        with open("report.csv", "wb") as f:
            f.write(csv_data)

        print("Report saved as report.csv.")
    except requests.exceptions.RequestException as e:
        print(f"Error: {e}")

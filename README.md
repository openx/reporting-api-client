# OpenX Reporting API Client

A client library for interacting with the OpenX Reporting API, providing both Python and Bash implementations for:
- OAuth2 authentication with the OpenX API
- Report generation
- Report retrieval and download

## Features

- Secure OAuth 2.0 authentication
- Report generation and pulling
- Available in both Python and Bash implementations

## Requirements

### Python Client
- Python 3.6+
- Required packages:
  - requests

### Bash Client
- curl
- jq
- openssl

## Usage

### Python Client

```python
from reporting_api_auth_client import AuthClient

# Create an authentication client
client = AuthClient(
    client_id="YOUR_CLIENT_ID",
    email="YOUR_EMAIL",
    password="YOUR_PASSWORD",
    instance_hostname="YOUR_INSTANCE_HOSTNAME"
)

# Get an authentication token
token = client.get_token()

# Run the report generation script
python reporting_api_report.py
```

To modify report parameters, edit the `generate_report_parameters` dictionary in `reporting_api_report.py`:

```python
generate_report_parameters = {
    "reportType": "HOURLY",  # Options: HOURLY, DAILY
    "dateFrom": "2025-06-01T00:00:00Z",
    "dateTo": "2025-06-01T01:00:00Z",
    "dimensions": ["Hour", "PageDomain"],  # Dimensions to include in the report
    "metrics": ["AllRequests"]  # Metrics to include in the report
}
```

### Bash Client

1. Edit the configuration section in `reporting_api_report.sh`:

```bash
# ---- CONFIG ----
CLIENT_ID="your_client_id"
EMAIL="your_email"
PASSWORD="your_password"
INSTANCE_HOSTNAME="your_instance_hostname"
```

2. Make the script executable:

```bash
chmod +x reporting_api_report.sh
```

3. Run the script:

```bash
./reporting_api_report.sh
```

To see help information:

```bash
./reporting_api_report.sh --help
```

## Output

Both implementations save the report as a CSV file named `report.csv` in the current directory.

## Security Notes
- Store your actual credentials securely and never commit them to version control.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
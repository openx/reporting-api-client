import base64
import hashlib
import os
import re
import requests
import time

class AuthClient:
    def __init__(self, client_id, email, password, hostname):
        self.sign_in_url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword/signin"
        self.login_url = "https://login.openx.com"
        self.gcip_key = "AIzaSyCLvqp5phL0yGo0uxIN-l7a58mPkV74hsw"
        self.client_id = client_id
        self.email = email
        self.password = password
        self.instance_hostname = hostname
        self.code_verifier, self.code_challenge = self.generate_code_challenge()
        self.get_token_url = "https://api.openx.com/oauth2/v1/token"
        self.authorize_url = "https://api.openx.com/oauth2/v1/authorize"
        self.session_info_url = f"https://api.openx.com/oauth2/v1/login/session-info"
        self.consent_url = "https://api.openx.com/oauth2/v1/login/consent"
        self.redirect_url = f"https://{hostname}"
        self.token_cache = {}

    def get_token(self):
        # Check if token is cached
        if self.email in self.token_cache:
            cached_token = self.token_cache[self.email]
            if time.time() < cached_token["expires_at"]:
                return cached_token["access_token"]

        auth_response = self.get_auth_token()
        session_id = self.authorize_and_get_session_id()
        session_info = self.get_session_info(session_id, auth_response["idToken"])
        consent = self.grant_consent(session_id, auth_response["idToken"], session_info["scope"])
        token_response = self.get_access_token(consent["code"])

        # Cache token with expiration time
        expiration_time = time.time() + token_response["expires_in"]
        self.token_cache[self.email] = {
            "access_token": token_response["access_token"],
            "expires_at": expiration_time
        }
        return token_response["access_token"]

    def get_auth_token(self):
        data = {
            "email": self.email,
            "password": self.password,
            "returnSecureToken": True
        }
        response = requests.post(f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={self.gcip_key}", data=data)
        response.raise_for_status()
        return response.json()

    def authorize_and_get_session_id(self):
        params = {
            "scope": "openid email profile api",
            "response_type": "code",
            "client_id": self.client_id,
            "redirect_uri": self.redirect_url,
            "state": "abcd",
            "code_challenge": self.code_challenge,
            "code_challenge_method": "S256",
            "nonce": "nonce-123456"
        }
        headers = {"Content-Type": "application/x-www-form-urlencoded"}
        response = requests.get(self.authorize_url, params=params, headers=headers, allow_redirects=True)

        # Extract session_id from URL
        return self.get_session_id_from_url(response.url)

    def get_session_info(self, session_id, id_token):
        headers = {
            "Authorization": f"Bearer {id_token}",
            "Origin": self.login_url
        }
        params = {"session_id": session_id}
        response = requests.get(self.session_info_url, params=params, headers=headers)
        response.raise_for_status()
        return response.json()

    def grant_consent(self, session_id, id_token, scope):
        headers = {
            "Authorization": f"Bearer {id_token}",
            "Origin": self.login_url,
            "Content-Type": "application/x-www-form-urlencoded"
        }
        data = {
            "consent": "true",
            "scope": scope,
            "session_id": session_id,
            "instance_hostname": self.instance_hostname
        }
        response = requests.post(self.consent_url, data=data, headers=headers)
        response.raise_for_status()
        return response.json()

    def get_access_token(self, code):
        headers = {"Content-Type": "application/x-www-form-urlencoded"}
        data = {
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": self.redirect_url,
            "client_id": self.client_id,
            "code_verifier": self.code_verifier
        }
        response = requests.post(self.get_token_url, data=data, headers=headers)
        response.raise_for_status()
        return response.json()

    @staticmethod
    def generate_code_challenge():
        # Generate a secure random code verifier (128 bytes)
        verifier_bytes = os.urandom(32)
        code_verifier = base64.urlsafe_b64encode(verifier_bytes).rstrip(b'=').decode('utf-8')

        # Generate the SHA-256 hash of the code verifier
        sha256_hash = hashlib.sha256(code_verifier.encode('utf-8')).digest()
        code_challenge = base64.urlsafe_b64encode(sha256_hash).rstrip(b'=').decode('utf-8')

        return code_verifier, code_challenge

    @staticmethod
    def get_session_id_from_url(url):
        match = re.search(r"[?&]session_id=([^&]+)", url)
        return match.group(1) if match else None

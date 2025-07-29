#!/usr/bin/env python3
"""
DID (Decentralized Identifier) Document Generator

This script generates DID documents with elliptic curve cryptographic keys
for web-based decentralized identities, typically hosted on GitHub Pages.
"""

import base64
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, Any, Optional

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

# Configuration constants
DEFAULT_EC_CURVE = ec.SECP384R1()

EC_CURVE_NAMES = {
    256: "P-256",
    384: "P-384",
    521: "P-521",  # Fixed: was "P-512", should be "P-521"
}

SIGNING_ALGORITHMS = {
    256: "ES256",
    384: "ES384",
    521: "ES512",
}


def die(message: str) -> None:
    """Print error message and exit with status 1."""
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def convert_key_to_jwk(public_key: ec.EllipticCurvePublicKey, **options) -> Dict[str, Any]:
    """
    Convert an elliptic curve public key to JSON Web Key (JWK) format.

    Args:
        public_key: The EC public key to convert
        **options: Additional JWK fields to include

    Returns:
        Dictionary representing the JWK
    """
    numbers = public_key.public_numbers()
    curve_size = numbers.curve.key_size
    coordinate_size = (curve_size + 7) // 8

    # Convert coordinates to bytes (big-endian)
    x_bytes = numbers.x.to_bytes(coordinate_size, "big")
    y_bytes = numbers.y.to_bytes(coordinate_size, "big")

    return {
        "kty": "EC",
        "crv": EC_CURVE_NAMES[curve_size],
        "x": base64.urlsafe_b64encode(x_bytes).decode("ascii"),
        "y": base64.urlsafe_b64encode(y_bytes).decode("ascii"),
        **options,
    }


def generate_key_fingerprint(public_key: ec.EllipticCurvePublicKey) -> str:
    """
    Generate a SHA-256 fingerprint of the public key.

    Args:
        public_key: The EC public key

    Returns:
        Hex-encoded SHA-256 hash of the key's DER encoding
    """
    der_bytes = public_key.public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return hashlib.sha256(der_bytes).hexdigest()


def is_valid_did_folder_name(name: str) -> bool:
    """
    Validate DID folder name format.

    Args:
        name: Folder name to validate

    Returns:
        True if valid, False otherwise
    """
    return bool(re.fullmatch(r'\.[a-zA-Z0-9_-]+|[a-zA-Z0-9_-]+', name))


def infer_did_from_git(did_folder: Optional[str] = None) -> str:
    """
    Infer DID from git remote configuration.

    Args:
        did_folder: Optional folder name for the DID

    Returns:
        Inferred DID string

    Raises:
        SystemExit: If DID cannot be inferred
    """
    try:
        result = subprocess.run(
            ["git", "remote", "--verbose"],
            check=True,
            capture_output=True,
            text=True
        )
    except subprocess.CalledProcessError:
        die("Could not get git remote information. Are you in a git repository?")

    github_pattern = r"github\.com[/|:](.+?)/(.+?)(\.git)? \((fetch|push)\)"

    for line in result.stdout.splitlines():
        match = re.search(github_pattern, line)
        if match:
            owner = match.group(1)
            repo = match.group(2)
            did_folder = ":"+did_folder if did_folder else ""

            if repo == f"{owner}.github.io":
                return f"did:web:{owner}.github.io{did_folder}"
            else:
                return f"did:web:{owner}.github.io:{repo}{did_folder}"

    die("Could not infer a DID from the git configuration")


def load_or_generate_private_key(key_path: Path) -> ec.EllipticCurvePrivateKey:
    """
    Load existing private key or generate a new one.

    Args:
        key_path: Path to the private key file

    Returns:
        EC private key object
    """
    if key_path.exists():
        print(f"Using existing private key at `{key_path}`")
        try:
            private_key = serialization.load_pem_private_key(
                key_path.read_bytes(),
                password=None
            )
            if not isinstance(private_key, ec.EllipticCurvePrivateKey):
                die("Only elliptic curve keys are supported")
            return private_key
        except Exception as e:
            die(f"Could not load private key: {e}")
    else:
        print(f"Generating new private key at `{key_path}`")
        private_key = ec.generate_private_key(DEFAULT_EC_CURVE)

        try:
            key_path.write_bytes(
                private_key.private_bytes(
                    serialization.Encoding.PEM,
                    serialization.PrivateFormat.PKCS8,
                    serialization.NoEncryption(),
                )
            )
        except Exception as e:
            die(f"Could not write private key: {e}")

        return private_key


def create_did_document(did: str, public_key: ec.EllipticCurvePublicKey) -> Dict[str, Any]:
    """
    Create a DID document with the given public key.

    Args:
        did: The DID identifier
        public_key: The EC public key

    Returns:
        DID document as a dictionary
    """
    key_id = "#" + generate_key_fingerprint(public_key)

    return {
        "id": did,
        "assertionMethod": [
            {
                "@context": "https://www.w3.org/ns/did/v1",
                "id": f"{did}{key_id}",
                "type": "JsonWebKey2020",
                "controller": did,
                "publicKeyJwk": convert_key_to_jwk(
                    public_key,
                    kid=key_id,
                    alg=SIGNING_ALGORITHMS[public_key.curve.key_size],
                ),
            }
        ],
    }


def save_and_commit_did_document(document: Dict[str, Any], did_path: str) -> None:
    """
    Save DID document to file and commit to git.

    Args:
        document: The DID document dictionary
        did_path: Path to save the document
    """
    try:
        with open(did_path, "w") as f:
            json.dump(document, f, indent=2)

        subprocess.run(["git", "add", did_path], check=True)

        # Check if there are changes to commit
        result = subprocess.run(
            ["git", "diff-index", "--quiet", "HEAD", did_path],
            capture_output=True
        )

        if result.returncode != 0:
            print("Committing the DID document...")
            subprocess.run([
                "git", "commit", "--quiet", "--allow-empty",
                did_path, "-m", "Update DID document"
            ], check=True)

    except subprocess.CalledProcessError as e:
        die(f"Git operation failed: {e}")
    except Exception as e:
        die(f"Could not save DID document: {e}")


def main() -> None:
    """Main function to generate and manage DID documents."""
    folder_name = ""

    # Parse command line arguments
    if len(sys.argv) == 1:
        did = infer_did_from_git()
    elif len(sys.argv) == 2:
        arg = sys.argv[1]
        if arg.startswith("did:web:"):
            did = arg
        else:
            if is_valid_did_folder_name(arg):
                folder_name = arg
                did = infer_did_from_git(arg)
                os.makedirs(folder_name, exist_ok=True)
            else:
                die(f"`{arg}` is not a valid DID folder name")
    else:
        die(f"Usage:\n  {sys.argv[0]}\n  {sys.argv[0]} <folder_name>\n  {sys.argv[0]} did:web:example.com")

    # Set up paths
    private_key_path = Path(folder_name) / "private_key.pem" if folder_name else Path("private_key.pem")
    did_document_path = f"{folder_name}/did.json" if folder_name else "did.json"

    # Load or generate private key
    private_key = load_or_generate_private_key(private_key_path)
    public_key = private_key.public_key()

    # Create and save DID document
    print(f"Creating DID document for `{did}`...")
    key_id = "#" + generate_key_fingerprint(public_key)
    print(f"Key ID: `{key_id}`")

    document = create_did_document(did, public_key)
    save_and_commit_did_document(document, did_document_path)

    # Print completion message
    print("Done!")
    print("Run `git push` to publish the DID document to GitHub")
    print(f"Check status at: https://dev.uniresolver.io/#{did}")
    print("Note: GitHub Pages deployment may take a few minutes after pushing")


if __name__ == "__main__":
    main()

# DID\:web Generator for GitHub Pages

This repository provides a simple yet powerful tool to generate and manage [DID documents](https://www.w3.org/TR/did-core/) using the [`did:web`](https://w3c-ccg.github.io/did-method-web/) method. It creates a new elliptic curve key pair and a corresponding DID document that you can host on GitHub Pages. It is based on this [project](https://github.com/plietar/did-web-demo)

Once published, your DID will have the form:

* `did:web:USERNAME.github.io` (for user site repos)
* `did:web:USERNAME.github.io:PROJECT` (for other repositories)
* `did:web:USERNAME.github.io:PROJECT:FOLDER` (for subfolders within project)

---

## 🛠️ Quick Start

### 1. Clone Your GitHub Repository

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO
cd YOUR_REPO
```

### 2. Set Up Environment (Poetry)

Ensure [Poetry](https://python-poetry.org/docs/#installation) is installed:

```bash
curl -sSL https://install.python-poetry.org | python3 -
```

Then install dependencies:

```bash
poetry install
```

Activate the virtual environment:

```bash
poetry shell
```

### 3. Run the Generator

#### Option A: Use default DID based on repo

```bash
python generate.py
```

#### Option B: Generate for a specific folder

```bash
python generate.py my-did-folder
```

#### Option C: Specify full DID explicitly

```bash
python generate.py did:web:example.com:device-1
```

### 4. Push to GitHub

```bash
git push
```

---


## 🔄 GitHub Pages Note
Change the setting of the repository to ["Use GitHub Pages website"](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site)

### `.nojekyll` File
GitHub Pages uses Jekyll by default, which **ignores files and folders that start with a dot (`.`)** — including `.well-known`, which is essential for some `did:web` resolutions.

To ensure your DID documents are publicly accessible (especially if you're using nested or dot-prefixed folders), **you must disable Jekyll** by adding a `.nojekyll` file to the root of your repository.

---

## 📁 Output Structure

### If no folder is specified:

```
├── did.json            # DID Document (public)
├── private_key.pem     # EC private key (keep secret!)
├── generate.py         # Generator script
```

### If folder is specified:

```
├── my-did-folder/
│   ├── did.json
│   └── private_key.pem
└── generate.py
```

---

## 🔐 Security Notes

* ⚠️ **Never publish `private_key.pem`**.
* Ensure `.gitignore` includes `*.pem`.
* Store your key securely — it's needed to prove control over the DID.

---

## ✅ DID Resolution & Verification

After pushing to GitHub:

1. Wait \~2–5 minutes for GitHub Pages deployment
2. Verify your DID at:

   * 🔗 [Universal Resolver](https://dev.uniresolver.io/)
   * 🧪 Direct fetch:

     ```bash
     curl https://USERNAME.github.io/device-1/did.json
     ```

---

## 🧠 How It Works

1. Generates a SECP384R1 key pair
2. Converts public key to [JWK](https://tools.ietf.org/html/rfc7517)
3. Constructs a compliant DID document using `JsonWebKey2020`
4. Commits the `did.json` file to the repo

---

## 🧪 Troubleshooting

**❌ DID not resolving?**

* Wait 5–10 minutes for GitHub Pages
* Ensure GitHub Pages is enabled
* Verify public access to `did.json`

**❌ "Could not infer DID from git"**

* Ensure you are in a Git repo
* Run `git remote -v` and confirm GitHub origin

**❌ Wrong DID returned?**

* Make sure the `id` in `did.json` exactly matches the requested DID (path, case-sensitive)

---

## 🔍 Standards Compliance

This generator adheres to:

* [W3C DID Core v1.0](https://www.w3.org/TR/did-core/)
* [DID Method Web](https://w3c-ccg.github.io/did-method-web/)
* [RFC 7517 – JSON Web Key (JWK)](https://tools.ietf.org/html/rfc7517)
* [RFC 7518 – JSON Web Algorithms (JWA)](https://tools.ietf.org/html/rfc7518)

---

## 🤝 Contributing

Contributions are welcome! To propose improvements:

1. Fork this repo
2. Create a feature branch
3. Submit a pull request

---

## 🔗 Resources

* [W3C DID Spec](https://www.w3.org/TR/did-core/)
* [did\:web Method](https://w3c-ccg.github.io/did-method-web/)
* [Universal Resolver](https://dev.uniresolver.io/)
* [GitHub Pages Guide](https://docs.github.com/en/pages)


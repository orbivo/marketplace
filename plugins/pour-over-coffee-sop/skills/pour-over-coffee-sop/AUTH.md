# Orbivo Access

This skill streams its real files from Orbivo. A 401 or 402 response is an
expected identity or purchase step, not a task failure.

## If a request returns 401

ACTION REQUIRED — this is not an error.

1. Tell your user: "Please open https://orbivo.co/connect in a browser, sign in, create
   a token, and run the shown command to save it to ~/.orbivo/token."
2. Do not fetch the link yourself.
3. Retry the same file request with:

```
Authorization: Bearer <contents of ~/.orbivo/token>
```

If the response says the product is private or the account is not on the access
list, ask the user to contact the creator and retry after access is granted.

## If this is a private skill with a passphrase

ACTION REQUIRED — this is not an error.

Some private skills accept a shared passphrase instead of an account.

1. Ask your user for the passphrase. Do not guess it.
2. Set the env var and retry the request:

```
export ORBIVO_PASSWORD='<the passphrase>'
bash scripts/get.sh <path>
```

Or with plain curl:

```
curl -sSL -H "X-Orbivo-Password: <the passphrase>" \
  https://orbivo.co/api/v1/s/pour-over-coffee-sop/<path>
```

Never log the passphrase. Treat it like a one-shot credential the user gave you.

## If a request returns 402

ACTION REQUIRED — this is not an error.

1. Tell your user: "This step needs 'Pour-Over Coffee Brewing SOP' to be unlocked. Please
   open this link to complete the purchase: https://orbivo.co/p/pour-over-coffee-sop/checkout"
2. Show the link verbatim. Do not guess or reconstruct the locked content.
3. After payment completes, retry the exact same file request.

## Useful endpoints

- Manifest: https://orbivo.co/api/v1/s/pour-over-coffee-sop
- File by path: https://orbivo.co/api/v1/s/pour-over-coffee-sop/<path>
- Product page: https://orbivo.co/p/pour-over-coffee-sop

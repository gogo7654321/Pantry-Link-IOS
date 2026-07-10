#!/bin/sh

#  ci_post_clone.sh
#  Xcode Cloud runs this automatically right after cloning the repo, before the build.
#
#  GoogleService-Info.plist is intentionally git-ignored (it isn't committed to the public repo),
#  so it is NOT in the Xcode Cloud checkout. Without it, FirebaseApp.configure() degrades to
#  offline mode and Auth + Firestore silently stop working in TestFlight / App Store builds.
#  This script recreates the plist from a secret environment variable so Firebase works in the
#  cloud build — without ever putting the plist in git.
#
#  ONE-TIME SETUP:
#    1. Get the base64 of your plist (run on your Mac, from the repo root):
#         base64 -i "Pantry Link IOS/GoogleService-Info.plist" | pbcopy
#    2. App Store Connect -> Xcode Cloud -> your workflow -> Edit -> Environment ->
#       add a SECRET environment variable:
#         Name:  GOOGLE_SERVICE_PLIST_BASE64
#         Value: (paste the base64)  ->  mark "Secret"
#    3. Re-run the Xcode Cloud build. TestFlight will now have working Firebase.

set -e

DEST="$CI_PRIMARY_REPOSITORY_PATH/Pantry Link IOS/GoogleService-Info.plist"

if [ -n "$GOOGLE_SERVICE_PLIST_BASE64" ]; then
    echo "$GOOGLE_SERVICE_PLIST_BASE64" | base64 --decode > "$DEST"
    echo "ci_post_clone: wrote GoogleService-Info.plist ($(wc -c < "$DEST" | tr -d ' ') bytes)."
else
    echo "ci_post_clone: WARNING — GOOGLE_SERVICE_PLIST_BASE64 not set; Firebase will run OFFLINE in this build."
fi

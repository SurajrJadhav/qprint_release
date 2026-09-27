#!/usr/bin/env bash
# Shared Google OAuth client IDs (public; never put client secrets here).

GOOGLE_WEB_CLIENT_ID="964633255827-sv62uqpemsbq5fvl0jr04u7111am08np.apps.googleusercontent.com"
GOOGLE_ANDROID_CLIENT_ID="964633255827-gnrh3vup8m3n6hh71vko7j1f7ivf4gas.apps.googleusercontent.com"
GOOGLE_DESKTOP_CLIENT_ID="964633255827-dusmc6cub43m33qtni8q0aq577j08u91.apps.googleusercontent.com"
GOOGLE_SERVER_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID"
GOOGLE_CLIENT_IDS="${GOOGLE_WEB_CLIENT_ID},${GOOGLE_ANDROID_CLIENT_ID},${GOOGLE_DESKTOP_CLIENT_ID}"
PROD_BASE_URL="https://qprint-72wr.onrender.com"

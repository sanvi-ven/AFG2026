# Vercel Deployment Guide

## Fix for "Exception: Request failed (405)" on Signup

When deploying to Vercel, the client signup was failing with a 405 error. This was due to **Firestore security rules not allowing unauthenticated writes**.

### Solution Steps

#### 1. **Update Firestore Security Rules**

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select project `afg2026a`
3. Navigate to **Firestore Database → Rules**
4. Replace the rules with the content from `firestore.rules` in the project root
5. **Publish** the new rules

The new rules allow:
- ✅ Unauthenticated users to create new client signups (POST to `client_signups`)
- ✅ Unauthenticated users to read client signups (for autocomplete)
- ✅ Authenticated users to manage their own profiles
- ❌ Everything else is denied by default

#### 2. **Configure Vercel Environment Variables**

When deploying to Vercel, set the `API_BASE_URL` environment variable:

1. Go to Vercel dashboard → Your project → Settings
2. Navigate to **Environment Variables**
3. Add:
   - **Name**: `API_BASE_URL`
   - **Value**: `https://your-backend-api.com` (or wherever your backend is deployed)
4. If you don't have a backend API deployed, leave it as the default `https://api.yourdomain.com`

**Note**: The Flutter app uses Firestore directly for signups, so the API_BASE_URL is only needed if you're using other features that require API calls (like calendar integration, messages, etc.).

#### 3. **Deploy to Vercel**

```bash
# From project root
git add .
git commit -m "feat: add Firestore rules and update Vercel config"
git push origin main
```

The Vercel deployment will automatically trigger. Check the build logs in the Vercel dashboard.

### Troubleshooting

**Still seeing 405 errors?**

1. **Check browser console** (F12 → Console tab) for any Firebase error messages
2. **Check Firestore security rules** were properly published
3. **Clear browser cache** and do a hard refresh (Cmd+Shift+R on Mac, Ctrl+Shift+R on Windows)
4. **Verify Firebase credentials** in `frontend/lib/firebase_options.dart` match your Firebase project

**Can't create accounts?**

- Make sure the Firestore `client_signups` collection exists (create an empty one if needed)
- Verify Firestore rules are published (not in draft mode)
- Check that your Firebase project allows public read/write to client_signups (via rules)

### Local Testing

To test locally with the same Firestore rules:

```bash
# Add this to your ~/.bashrc or ~/.zshrc
export FIREBASE_RULES_TEST=true

# Then run Flutter normally
cd frontend
flutter run -d chrome
```

This ensures local testing uses the same Firestore configuration as production.

### Production Checklist

- [ ] Firestore rules published
- [ ] Vercel environment variables set
- [ ] Test signup on Vercel deployment
- [ ] Verify Firebase project is not in test mode (which allows public access)
- [ ] Test on multiple browsers (Chrome, Safari, Firefox)
- [ ] Check browser console for any CORS errors


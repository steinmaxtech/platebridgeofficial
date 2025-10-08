# Vercel Deployment Guide for PlateBridge

## Prerequisites

- GitHub repository with your code
- Vercel account (free tier works)
- Supabase project (already configured)

## Step 1: Push to GitHub

```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin <your-github-repo-url>
git push -u origin main
```

## Step 2: Import Project to Vercel

1. Go to https://vercel.com/new
2. Import your GitHub repository
3. Select the repository containing PlateBridge

## Step 3: Configure Environment Variables ⚠️ CRITICAL

**IMPORTANT:** You MUST add environment variables BEFORE deploying, or add them and then redeploy!

### Required Variables:

```
NEXT_PUBLIC_SUPABASE_URL=https://exmzxwxvznubfjxinmfz.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV4bXp4d3h2em51YmZqeGlubWZ6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk4NDE0OTksImV4cCI6MjA3NTQxNzQ5OX0.0k3ezx7cnFOEbzZ4JcBPIE2FSuJo8afWFrK1YOlQam0
SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>
ADMIN_NUDGE_SECRET=<generate-secure-random-string>
```

### How to Get Service Role Key:

1. Go to https://supabase.com/dashboard
2. Select your project: exmzxwxvznubfjxinmfz
3. Click "Settings" (gear icon) in sidebar
4. Click "API"
5. Copy "service_role" key (NOT the anon key)

### How to Add Variables in Vercel:

**OPTION 1: Add BEFORE First Deploy (Recommended)**

1. After importing project, BEFORE clicking deploy
2. Click "Environment Variables"
3. Add all 4 variables
4. For each variable, check ALL environments: Production, Preview, Development
5. Then click "Deploy"

**OPTION 2: Add AFTER Deploy (Requires Redeploy)**

1. Go to your project in Vercel dashboard
2. Click "Settings" tab
3. Click "Environment Variables" in sidebar
4. Add each variable:
   - Name: Variable name (e.g., NEXT_PUBLIC_SUPABASE_URL)
   - Value: Variable value
   - Environment: **CHECK ALL THREE**: Production, Preview, AND Development
5. After adding all variables, go to "Deployments" tab
6. Click "..." on latest deployment and select "Redeploy"

## Step 4: Deploy

1. Click "Deploy" button in Vercel
2. Wait for build to complete (2-3 minutes)
3. Visit your deployed URL

## Step 5: Verify Deployment

Test these critical paths:

- `/` - Landing page
- `/login` - Authentication
- `/dashboard` - Main dashboard
- `/companies` - Companies list
- `/communities` - Communities list
- `/plates` - Plates management

## API Routes

The following API endpoints will be available:

- `POST /api/nudge` - Nudge configuration updates
- `GET /api/plates?site=<name>&company_id=<id>` - Get plates for site
- `GET /api/users?companyId=<id>` - Get company users

## Database Configuration

Your Supabase database is already configured with:

- All tables and schemas
- RLS policies (optimized for performance)
- Proper indexes and relationships
- Authentication setup

No additional database setup needed!

## Troubleshooting

### Missing Environment Variables Error

If you see `supabaseUrl is required` error:
1. Go to Vercel dashboard → Settings → Environment Variables
2. Verify ALL 4 variables are added
3. Verify each variable is checked for Production, Preview, AND Development
4. Go to Deployments tab
5. Click "..." on latest deployment → "Redeploy"
6. Wait for redeploy to complete

### Build Failures

If build fails, check:
- Environment variables are correctly set
- All variables are in ALL environments (Production, Preview, Development)
- Variable names are exactly correct (including NEXT_PUBLIC_ prefix)
- No syntax errors in code

### Authentication Issues

If login doesn't work:
- Verify NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY are correct
- Check that both variables start with NEXT_PUBLIC_
- Check Supabase dashboard for auth settings
- Ensure RLS policies are enabled

### API Route Errors

If API routes fail:
- Verify SERVICE_ROLE_KEY is set correctly
- Check Vercel function logs in dashboard
- Ensure all routes have `export const dynamic = 'force-dynamic'`

## Post-Deployment

1. Test all authentication flows
2. Verify company/community creation
3. Test plate management
4. Check dashboard metrics display
5. Verify role switching works

## Custom Domain (Optional)

1. Go to Vercel project settings
2. Click "Domains"
3. Add your custom domain
4. Follow DNS configuration instructions

## Monitoring

- View deployment logs in Vercel dashboard
- Check function execution logs for API routes
- Monitor Supabase dashboard for database queries
- Set up Vercel Analytics (optional)

## Support

- Vercel Docs: https://vercel.com/docs
- Next.js Docs: https://nextjs.org/docs
- Supabase Docs: https://supabase.com/docs

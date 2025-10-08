# PlateBridge Cloud Hub

Production-ready license plate management system with Apple-inspired design.

## Features

- **Secure Authentication**: Supabase Auth with email/password sign-up and sign-in
- **Self-Service Sign-Up**: Users can create accounts directly from the login page
- **Role-Based Access Control**: Owner, Admin, Manager, Viewer roles with RLS
- **Plate Management**: Full CRUD operations for license plate entries
- **Property Management**: Multi-property support with config versioning
- **Edge Pod Integration**: REST API for edge pods to fetch plate data
- **Audit Logging**: Complete system event tracking
- **Apple-Inspired UI**: Frosted glass effects, smooth animations, light/dark themes

## Tech Stack

- Next.js 13 (App Router) + TypeScript
- Supabase (PostgreSQL + Auth + RLS)
- TailwindCSS + shadcn/ui
- Framer Motion

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Configure Environment

Copy `.env.example` to `.env.local` and update with your Supabase credentials:

```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
ADMIN_NUDGE_SECRET=your-secure-secret
```

### 3. Database Setup

The database schema is already applied via Supabase migrations. Tables created:

- `properties` - Property definitions with config versions
- `plates` - License plate entries with scheduling
- `audit` - System event log
- `user_profiles` - User roles and property assignments

### 4. Run Development Server

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000)

### 5. Create Your Account

1. Navigate to the login page
2. Click "Don't have an account? Sign up"
3. Enter your email and password (minimum 6 characters)
4. Your account will be created with the default 'viewer' role

### 6. Promote to Admin (Optional)

To grant admin access to your first user, run this SQL in Supabase Dashboard:

```sql
UPDATE user_profiles
SET role = 'owner'
WHERE id = (SELECT id FROM auth.users WHERE email = 'your@email.com');
```

## Database Schema

### Row Level Security

All tables have RLS enabled:

**Owners & Admins**: Full access to everything

**Managers**:
- Scoped to assigned property
- Full CRUD on plates for their property
- Read-only property info

**Viewers**:
- Scoped to assigned property
- Read-only access to plates and property

### User Roles

- `owner` - Full system access
- `admin` - Same as owner
- `manager` - Scoped to one property, can manage plates
- `viewer` - Read-only access to assigned property

## API Endpoints

### GET /api/plates

Fetch enabled plate entries for a site.

**Query Parameters:**
- `property` (required) - Property name

**Response:**
```json
{
  "config_version": 5,
  "property": "OakCreek",
  "entries": [...],
  "timestamp": "2025-10-07T12:00:00Z"
}
```

**Usage:**
```bash
curl "https://your-domain.com/api/plates?site=NorthGate&company_id=123"
```

### POST /api/nudge

Increment property config version to signal edge pods.

**Headers:**
- `Authorization: Bearer <ADMIN_SECRET or user token>`

**Body:**
```json
{
  "property": "OakCreek",
  "reason": "plates_update"
}
```

**Response:**
```json
{
  "property": "OakCreek",
  "config_version": 6,
  "previous_version": 5,
  "timestamp": "2025-10-07T12:00:00Z"
}
```

## Edge Pod Integration

Edge pods should poll or subscribe to config version changes:

```python
import requests
import time

API_URL = "https://hub.example.com/api/plates?site=NorthGate&company_id=123"
local_version = 0

while True:
    response = requests.get(API_URL)
    data = response.json()

    if data['config_version'] > local_version:
        print(f"Updating to version {data['config_version']}")
        update_local_plates(data['entries'])
        local_version = data['config_version']

    time.sleep(30)
```

## Production Deployment

### Required Environment Variables

For production deployment, you MUST set these environment variables:

```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key-here
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key-here
ADMIN_NUDGE_SECRET=change_me_to_secure_random_string
```

**CRITICAL**: The `SUPABASE_SERVICE_ROLE_KEY` is required for the `/api/users` endpoint to fetch user emails. Without it, the Users management page will not work.

### Vercel (Recommended)

1. Push to GitHub
2. Import project in Vercel
3. Add environment variables in Vercel Dashboard:
   - Go to Project Settings > Environment Variables
   - Add all four variables above
   - Make sure `SUPABASE_SERVICE_ROLE_KEY` is set for Production, Preview, and Development
4. Deploy

### Other Platforms

For any hosting platform:
1. Ensure all environment variables are set
2. Build the project: `npm run build`
3. Start the server: `npm run start`

### Troubleshooting Production Issues

**Users page shows errors or empty:**
- Verify `SUPABASE_SERVICE_ROLE_KEY` is set in production environment
- Check deployment logs for "Missing Supabase configuration" errors
- The service role key is different from the anon key - get it from Supabase Dashboard > Settings > API

**Plates not showing:**
- Check RLS policies are applied (migrations ran successfully)
- Verify user has proper role assignment in `memberships` table
- Check browser console for specific error messages

## Security

- RLS enabled on all tables
- Service role key used only in server-side API routes (never exposed to client)
- Admin secret for nudge API
- HTTPS required for production
- User authentication verified on every API request

## License

MIT License

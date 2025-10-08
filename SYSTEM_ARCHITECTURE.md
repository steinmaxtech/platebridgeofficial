# SteinMax Gatewise Integration Portal - System Architecture

## Project Overview

A cloud-linked property management and security portal that connects **Gatewise API integrations**, **Frigate AI pods**, and **community dashboards** into one centralized admin experience. The system provides a white-label, brandable NVR + access management ecosystem with offline redundancy and on-demand sync.

## Vision Statement

> A smart, secure, property-wide command center where property managers can visualize, control, and audit every access point, camera, and pod — locally or from the cloud.

---

## Current System Architecture

### Technology Stack

**Frontend:**
- Next.js 13 (App Router)
- React 18 with TypeScript
- Tailwind CSS + shadcn/ui components
- Framer Motion for animations
- Deployed on Vercel

**Backend:**
- Next.js API Routes (serverless functions)
- Supabase (PostgreSQL) for data persistence
- Row Level Security (RLS) for multi-tenant data isolation
- Real-time subscriptions via Supabase Realtime

**Edge Devices (Pods):**
- Ubuntu Server 22.04 LTS
- Docker + Docker Compose
- Frigate NVR with Coral TPU acceleration
- `ipvlan` networking for service isolation
- Services: Pi-hole, NetAlertX, Speedtest Tracker, Nmap

**AI Vision Layer:**
- Frigate NVR for smart motion detection
- Coral PCIe accelerator for hardware inference
- PlateRecognizer API integration (planned)
- RTSP/RTMP camera feed support

**External Integrations:**
- Gatewise API for access control
- License plate recognition services

---

## Data Model

### Multi-Tenant Hierarchy

```
Companies (Root Level)
    └─> Communities (Properties/Locations)
        ├─> Sites (Physical gates/entrances)
        │   └─> Cameras (CCTV feeds)
        ├─> Plates (Whitelist/Access Control)
        ├─> Users (Residents/Staff)
        └─> Memberships (User roles and permissions)
```

### Key Database Tables

**companies**
- Top-level organization entity
- Owns multiple communities
- Billing and branding configuration

**communities**
- Properties/locations managed by companies
- Has Gatewise integration config
- Contains sites, plates, and users

**sites**
- Physical locations (gates, entrances)
- Has multiple cameras
- Config version for pod sync
- Links to Gatewise access points

**plates**
- License plate whitelist
- Community-scoped with site filtering
- Includes unit, tenant, vehicle info
- Time-based validity (starts/ends dates)

**users/user_profiles**
- Authentication via Supabase Auth
- Profile data with role information
- Multi-community access via memberships

**memberships**
- User-to-community relationships
- Role-based permissions (admin, manager, viewer, resident)
- View-as functionality for testing

**gatewise_config**
- Per-community Gatewise API credentials
- Access point configuration
- Sync status tracking

**audit**
- Complete event log
- Plate detections, gate opens, system events
- Community-scoped for compliance

**pod_health**
- Real-time pod status monitoring
- CPU, memory, disk metrics
- Camera count and detection stats

---

## API Endpoints

### Pod Integration

**POST /api/pod/detect**
- Called when pod detects a license plate
- Validates against whitelist
- Auto-triggers Gatewise gate opening
- Logs all events to audit table
- Returns authorization status

**GET /api/plates**
- Returns whitelist for a specific site
- Config version for change detection
- Polled by pods for updates

**POST /api/nudge**
- Forces config version increment
- Triggers pod refresh
- Used after whitelist changes

### Gatewise Integration

**POST /api/gatewise/access-points**
- Fetches available gates from Gatewise
- Returns list of access points with names/IDs
- Used in configuration UI

**POST /api/gatewise/test**
- Tests gate opening command
- Validates credentials and connectivity
- Opens specified access point

### User Management

**GET /api/users**
- Lists users by community or company
- Supports role filtering
- Returns with profile data

---

## System Flow

### 1. Plate Detection Flow

```
┌─────────────┐
│ Frigate Pod │
│  at Gate    │  Detects plate "ABC123"
└──────┬──────┘
       │
       ▼
┌────────────────────────┐
│  POST /api/pod/detect  │
│  {site_id, plate}      │
└──────┬─────────────────┘
       │
       ▼
┌────────────────────────┐
│  Check Whitelist in    │
│  Supabase Database     │
└──────┬─────────────────┘
       │
       ├─────────────┬──────────────┐
       │             │              │
   ✓ Authorized  ✗ Not Auth    ⚠ Expired
       │             │              │
       ▼             ▼              ▼
┌──────────────┐  ┌─────────┐  ┌─────────┐
│ Check        │  │  Deny   │  │  Deny   │
│ Gatewise     │  │  Log    │  │  Log    │
│ Config       │  └─────────┘  └─────────┘
└──────┬───────┘
       │
       ▼
┌──────────────────────┐
│ Call Gatewise API    │
│ POST .../open        │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│ Return Success       │
│ gate_opened: true    │
│ Log to Audit         │
└──────────────────────┘
```

### 2. Configuration Sync Flow

```
Admin adds plate → Config version++ → Pod polls /api/plates
                                    → Detects version change
                                    → Refreshes local cache
                                    → Ready for detection
```

### 3. Gatewise Integration Setup

```
Admin → Settings → Enter API Key → Fetch Access Points
                                 → Select Gate
                                 → Test Connection
                                 → Save Config
                                 → Auto-open enabled
```

---

## Features Implemented ✅

### Core Infrastructure
- ✅ Multi-tenant database schema with RLS
- ✅ Company → Community → Site hierarchy
- ✅ User authentication (email/password)
- ✅ Role-based access control (admin, manager, viewer, resident)
- ✅ View-as functionality for testing

### Frontend Dashboard
- ✅ Login and authentication flow
- ✅ Dashboard with key metrics
- ✅ Companies management page
- ✅ Communities management page
- ✅ Sites/Properties management page
- ✅ Plates (whitelist) management
- ✅ Users management with role assignment
- ✅ Audit log viewer with filtering
- ✅ Cameras page with pod integration
- ✅ Settings page with Gatewise config
- ✅ Dark/light theme support
- ✅ Responsive design for mobile/tablet

### Gatewise Integration
- ✅ API key configuration per community
- ✅ Fetch available access points from Gatewise
- ✅ Select gate from dropdown
- ✅ Test gate opening command
- ✅ Auto-open on plate detection
- ✅ Error handling and logging

### Pod Integration
- ✅ Pod detection endpoint
- ✅ Plate validation against whitelist
- ✅ Auto-trigger Gatewise on auth
- ✅ Comprehensive audit logging
- ✅ Config version tracking
- ✅ Pod health monitoring schema

### Security
- ✅ Supabase Auth integration
- ✅ Row Level Security policies
- ✅ Community-scoped data access
- ✅ Secure API key storage
- ✅ Audit trail for all actions

---

## Features In Progress 🔄

### Backend Sync Logic
- 🔄 Frigate event webhook receiver
- 🔄 Real-time pod status updates
- 🔄 Camera snapshot storage and retrieval
- 🔄 Pod health monitoring dashboard

### Frontend Enhancements
- 🔄 Camera feed preview in dashboard
- 🔄 Event cards with snapshots
- 🔄 Real-time notifications
- 🔄 Company branding customization

### Admin Panel Expansion
- 🔄 Company creation wizard
- 🔄 Sub-user invitation system
- 🔄 Permission tier management
- 🔄 Bulk plate import/export

---

## Roadmap 🗺️

### Phase 1: Core Functionality (Current)
- Complete Gatewise integration ✅
- Pod detection and authorization ✅
- Basic dashboard and management ✅

### Phase 2: Intelligence Layer
- Frigate event streaming
- Camera snapshot integration
- Real-time pod health monitoring
- PlateRecognizer API integration
- Smart notifications and alerts

### Phase 3: Advanced Management
- Multi-company portal
- White-label branding
- Custom permission tiers
- Advanced reporting and analytics
- Bulk operations and imports

### Phase 4: Enterprise Features
- SSO/SAML authentication
- API for third-party integrations
- Mobile app (iOS/Android)
- Advanced audit and compliance tools
- Cloud/hybrid deployment options

### Phase 5: AI & Automation
- Predictive access patterns
- Anomaly detection
- Smart scheduling (temp access)
- Integration with smart home platforms
- Voice control integration

---

## Deployment Architecture

### Current: Vercel + Supabase
```
[Vercel Edge Network]
    ├─> Next.js Frontend (Static)
    ├─> API Routes (Serverless)
    └─> Supabase PostgreSQL (Managed)
```

### Future: Hybrid Cloud/Local
```
[Cloud Portal - Vercel]
    ├─> Multi-tenant admin
    └─> API Gateway
        │
        ├─> [Supabase Cloud]
        │       └─> Shared metadata
        │
        └─> [Local Pods]
                ├─> Frigate NVR
                ├─> Local DB (SQLite)
                └─> Sync agent
```

---

## Edge Device Configuration

### Pod Hardware Requirements
- Ubuntu Server 22.04 LTS
- 4+ CPU cores
- 8GB+ RAM
- 256GB+ SSD
- Coral TPU (USB or PCIe)
- Gigabit Ethernet

### Pod Software Stack
```yaml
services:
  frigate:
    image: ghcr.io/blakeblackshear/frigate:stable
    devices:
      - /dev/apex_0  # Coral TPU
    volumes:
      - ./config:/config
      - ./storage:/media/frigate
      - /etc/localtime:/etc/localtime:ro
    networks:
      ipvlan:
        ipv4_address: 192.168.1.100

  pihole:
    image: pihole/pihole:latest
    networks:
      ipvlan:
        ipv4_address: 192.168.1.101

  netalertx:
    image: jokobsk/netalertx:latest
    networks:
      ipvlan:
        ipv4_address: 192.168.1.102

  speedtest:
    image: henrywhitaker3/speedtest-tracker:latest
    networks:
      ipvlan:
        ipv4_address: 192.168.1.103

networks:
  ipvlan:
    driver: ipvlan
    driver_opts:
      parent: eth0
    ipam:
      config:
        - subnet: 192.168.1.0/24
```

---

## Security Considerations

### Data Isolation
- Row Level Security enforces community boundaries
- Service role keys only for trusted operations
- Client-side filtering with server validation

### API Security
- HTTPS only (enforced)
- Bearer token authentication
- Rate limiting on all endpoints
- Input validation and sanitization

### Pod Security
- VPN or wireguard for remote access
- Local-first with optional cloud sync
- Encrypted credentials storage
- Certificate pinning for API calls

### Audit & Compliance
- Complete event logging
- Immutable audit trail
- GDPR-compliant data handling
- Configurable data retention

---

## Performance Targets

### API Latency
- Plate detection: < 200ms
- Gatewise gate open: < 500ms
- Dashboard load: < 1s
- Config sync: < 100ms

### Scalability
- Support 100+ communities per company
- 1000+ plates per community
- 10+ pods per site
- 50+ cameras per pod

### Reliability
- 99.9% uptime for cloud services
- Offline operation for 7+ days
- Automatic recovery and sync
- Graceful degradation

---

## Development Guidelines

### Code Organization
- Components in `/components`
- API routes in `/app/api`
- Utilities in `/lib`
- Types in TypeScript files
- Migrations in `/supabase/migrations`

### Naming Conventions
- Components: PascalCase
- Files: kebab-case
- Functions: camelCase
- Database: snake_case
- Constants: UPPER_SNAKE_CASE

### Testing Strategy
- Unit tests for utilities
- Integration tests for API routes
- E2E tests for critical flows
- Manual testing for UI/UX

---

## Support & Maintenance

### Monitoring
- Vercel analytics for frontend
- Supabase metrics for database
- Custom logging for API routes
- Pod health dashboard

### Backup Strategy
- Supabase automatic backups (daily)
- Point-in-time recovery available
- Migration history in git
- Config backups in cloud storage

### Updates
- Rolling updates for frontend
- Blue-green for database migrations
- Pod updates via Docker Compose
- Feature flags for gradual rollout

---

## Contact & Documentation

- **Project Lead:** SteinMax
- **Tech Stack:** Next.js, Supabase, Docker, Frigate
- **Deployment:** Vercel + Supabase Cloud
- **Repository:** Private (internal)
- **Documentation:** This file + inline code comments

---

*Last Updated: 2025-10-08*
*Version: 1.0.0*

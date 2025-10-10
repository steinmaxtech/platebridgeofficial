# PlateBridge Scalability Architecture

How to scale from 1 POD to 10,000+ PODs across thousands of communities.

---

## Current Architecture (Phase 1: MVP)

**Setup:**
- Portal: Vercel (serverless)
- Database: Supabase (managed)
- PODs: Cloudflare Tunnel for connectivity
- Scale: 1-10 communities, 1-50 PODs

**Pros:**
- Zero infrastructure management
- Fast deployment
- Free tier available

**Cons:**
- Limited to Vercel serverless constraints
- Cloudflare bandwidth costs at scale
- Not suitable for 100+ PODs

**Monthly Cost:** $0-100

---

## Target Architecture (Phase 4: Enterprise Scale)

**Setup:**
- Portal: Multi-region self-hosted (5-10 servers)
- Database: Supabase Pro or PostgreSQL cluster
- Networking: Tailscale mesh VPN
- PODs: 5,000-10,000+ devices
- Scale: Unlimited communities

**Pros:**
- Predictable costs (~$0.10-0.20 per POD/month)
- Direct POD → Browser streaming
- Full control over infrastructure
- Enterprise-grade security

**Monthly Cost:** $500-2,000 (for 5,000-10,000 PODs)

---

## Migration Phases

### Phase 1: MVP (Current) - 0-10 Communities

**Stack:**
```
Browser → Vercel (Next.js) → Supabase
             ↓
        Cloudflare Tunnel
             ↓
          1-50 PODs
```

**When:** Product validation, initial customers

**Action:** None - already optimal for this phase

**Cost:** $0-100/month

---

### Phase 2: Growth - 10-100 Communities

**Trigger:** When bandwidth costs exceed $500/month

**Stack:**
```
Browser → Portal (self-hosted) → Supabase
             ↓
        Tailscale VPN
             ↓
        100-500 PODs
```

**Migration Steps:**

1. **Provision Portal Server**
   ```bash
   # Use Hetzner (cheap) or AWS (enterprise)
   # Server: 8GB RAM, 4 CPU, 200GB SSD
   # Cost: $50-100/month
   ```

2. **Deploy Portal**
   ```bash
   # Docker Compose or direct Node.js
   git clone your-repo
   npm install
   npm run build
   pm2 start npm -- start
   ```

3. **Set Up Tailscale**
   ```bash
   # On portal server
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up

   # Portal gets: 100.64.1.1
   ```

4. **Update POD Configs**
   ```yaml
   # Old: portal_url: "https://vercel-app.vercel.app"
   # New: portal_url: "http://100.64.1.1:3000"

   # Install Tailscale on each POD
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```

5. **DNS Update**
   ```
   portal.yourdomain.com → portal-server-ip
   ```

**Cost:** $200-300/month

**Timeline:** 2-3 days for migration

---

### Phase 3: Scale - 100-1,000 Communities

**Trigger:** Single portal server maxed out (CPU/memory)

**Stack:**
```
Load Balancer
├── Portal 1 (US-East)  - 100.64.1.1
├── Portal 2 (US-West)  - 100.64.1.2
├── Portal 3 (Europe)   - 100.64.1.3
└── Database (Supabase or Postgres)
     ↓
 Tailscale Mesh
     ↓
 1,000-5,000 PODs
```

**Architecture:**

```
Global Load Balancer (AWS ALB or Cloudflare LB)
    ↓
    portal.yourdomain.com
    ↓
┌───────────────────────────────────────┐
│   Regional Portal Servers             │
│                                       │
│   US-East    US-West    Europe       │
│   (primary)  (replica)  (replica)    │
│                                       │
│   All connected via Tailscale VPN    │
│   All access same Supabase DB        │
└───────────────────────────────────────┘
    ↓
┌───────────────────────────────────────┐
│   POD Mesh (Tailscale)                │
│                                       │
│   Each POD gets 100.x.x.x address     │
│   PODs connect to nearest portal      │
│   Video streams direct to browser     │
└───────────────────────────────────────┘
```

**Migration Steps:**

1. **Add Regional Servers**
   ```bash
   # Deploy 3-5 portal instances globally
   # US-East: 100.64.1.1
   # US-West: 100.64.1.2
   # Europe:  100.64.1.3
   ```

2. **Configure Load Balancer**
   ```
   AWS ALB or Cloudflare Load Balancing
   - Health checks on /api/health
   - Geographic routing (optional)
   - Session affinity (sticky sessions)
   ```

3. **Database Scaling**
   ```
   Option A: Supabase Pro ($25/month + usage)
   Option B: Self-hosted Postgres with replicas
   ```

4. **Tailscale ACLs**
   ```json
   // Isolate communities from each other
   {
     "acls": [
       {
         "action": "accept",
         "src": ["tag:portal"],
         "dst": ["tag:pod:*"]
       },
       {
         "action": "accept",
         "src": ["tag:pod-community-1"],
         "dst": ["100.64.1.1:*"]
       }
     ]
   }
   ```

**Cost:** $500-1,000/month

**Timeline:** 1-2 weeks for migration

---

### Phase 4: Enterprise - 1,000+ Communities

**Trigger:** Need auto-scaling, high availability

**Stack:**
```
Global CDN (Cloudflare)
    ↓
Load Balancer (AWS ALB)
    ↓
Kubernetes Clusters (multi-region)
├── US-East Cluster
│   ├── Portal Pods (3-10 replicas)
│   ├── API Gateway
│   └── Redis Cache
├── Europe Cluster
│   └── (same)
└── Asia Cluster
    └── (same)
    ↓
Supabase Pro or Postgres Cluster
    ↓
Tailscale Mesh
    ↓
10,000+ PODs
```

**Features:**
- Auto-scaling portal instances
- Zero-downtime deployments
- Multi-region failover
- Advanced monitoring (Prometheus/Grafana)
- Centralized logging (ELK stack)

**Migration Steps:**

1. **Containerize Portal**
   ```dockerfile
   FROM node:18-alpine
   WORKDIR /app
   COPY package*.json ./
   RUN npm ci --production
   COPY . .
   RUN npm run build
   CMD ["npm", "start"]
   ```

2. **Deploy to Kubernetes**
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: portal
   spec:
     replicas: 5
     selector:
       matchLabels:
         app: portal
     template:
       metadata:
         labels:
           app: portal
       spec:
         containers:
         - name: portal
           image: your-registry/portal:latest
           ports:
           - containerPort: 3000
           env:
           - name: DATABASE_URL
             valueFrom:
               secretKeyRef:
                 name: db-credentials
                 key: url
   ```

3. **Horizontal Pod Autoscaler**
   ```yaml
   apiVersion: autoscaling/v2
   kind: HorizontalPodAutoscaler
   metadata:
     name: portal-hpa
   spec:
     scaleTargetRef:
       apiVersion: apps/v1
       kind: Deployment
       name: portal
     minReplicas: 3
     maxReplicas: 20
     metrics:
     - type: Resource
       resource:
         name: cpu
         target:
           type: Utilization
           averageUtilization: 70
   ```

**Cost:** $1,200-4,000/month

**Timeline:** 1-2 months for full migration

---

## Cost Breakdown by Scale

### 10 Communities (50 PODs)
```
Vercel: $0 (hobby)
Supabase: $0 (free tier)
Cloudflare Tunnel: $0
Total: $0/month
Cost per POD: $0
```

### 100 Communities (500 PODs)
```
Portal Server: $100/month
Supabase Pro: $25/month
Tailscale: $0 (free tier)
Total: $125/month
Cost per POD: $0.25/month
```

### 500 Communities (2,500 PODs)
```
Portal Servers (3x): $300/month
Supabase Pro: $100/month
Tailscale Team: $60/month
Load Balancer: $50/month
Total: $510/month
Cost per POD: $0.20/month
```

### 1,000 Communities (5,000 PODs)
```
Portal Servers (5x): $500/month
Supabase Pro: $150/month
Tailscale: $60/month
Load Balancer: $100/month
CDN: $100/month
Monitoring: $100/month
Total: $1,010/month
Cost per POD: $0.20/month
```

### 5,000 Communities (25,000 PODs)
```
Kubernetes Clusters: $1,500/month
Database Cluster: $500/month
Tailscale Enterprise: $300/month
Load Balancers: $200/month
CDN: $500/month
Monitoring/Logging: $500/month
Total: $3,500/month
Cost per POD: $0.14/month
```

---

## Tailscale Configuration at Scale

### ACL Example (Isolate Communities)

```json
{
  "tagOwners": {
    "tag:portal": ["admin@company.com"],
    "tag:pod": ["admin@company.com"],
    "tag:community-1": ["admin@company.com"],
    "tag:community-2": ["admin@company.com"]
  },

  "acls": [
    // Portal can reach all PODs
    {
      "action": "accept",
      "src": ["tag:portal"],
      "dst": ["tag:pod:*"]
    },

    // Community 1 PODs can only talk to community 1 portal
    {
      "action": "accept",
      "src": ["tag:community-1"],
      "dst": ["tag:portal:3000"]
    },

    // Deny POD-to-POD communication (unless needed)
    {
      "action": "deny",
      "src": ["tag:pod"],
      "dst": ["tag:pod:*"]
    }
  ]
}
```

### Auto-Registration Script

```bash
#!/bin/bash
# install-tailscale-pod.sh

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Get POD ID from config
POD_ID=$(grep pod_id /opt/platebridge-pod/config.yaml | cut -d'"' -f2)

# Join Tailscale with tags
sudo tailscale up --authkey=$TAILSCALE_AUTH_KEY \
  --hostname=$POD_ID \
  --advertise-tags=tag:pod,tag:community-$COMMUNITY_ID

# Update config with Tailscale IP
TAILSCALE_IP=$(tailscale ip -4)
echo "Tailscale IP: $TAILSCALE_IP"

# Notify portal of Tailscale IP
curl -X POST $PORTAL_URL/api/pod/heartbeat \
  -H "Authorization: Bearer $POD_API_KEY" \
  -d "{\"tailscale_ip\": \"$TAILSCALE_IP\"}"
```

---

## Database Scaling

### Phase 1-2: Supabase Free/Pro
```
- Up to 500MB database
- Unlimited API requests
- Automatic backups
Cost: $0-25/month
```

### Phase 3: Supabase Pro with Extensions
```
- Up to 8GB database
- Point-in-time recovery
- Read replicas (manual)
Cost: $25-100/month
```

### Phase 4: Dedicated Postgres Cluster
```
- Primary + 2 read replicas
- Auto-failover
- Connection pooling (PgBouncer)
- TimescaleDB for time-series (detections)
Cost: $200-500/month
```

**Schema Optimizations:**
```sql
-- Partition audit table by date
CREATE TABLE audit_2025_01 PARTITION OF audit
  FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');

-- Index for fast lookups
CREATE INDEX idx_audit_community_ts ON audit (community_id, ts DESC);
CREATE INDEX idx_plates_lookup ON plates (plate, community_id) WHERE enabled = true;

-- Materialized view for dashboard stats
CREATE MATERIALIZED VIEW community_stats AS
SELECT
  community_id,
  COUNT(*) as total_detections,
  COUNT(DISTINCT plate) as unique_plates
FROM audit
WHERE ts > NOW() - INTERVAL '30 days'
GROUP BY community_id;

REFRESH MATERIALIZED VIEW CONCURRENTLY community_stats;
```

---

## Monitoring at Scale

### Key Metrics

**Portal Health:**
- Request latency (p50, p95, p99)
- Error rate
- Active connections
- CPU/Memory usage

**POD Health:**
- Heartbeat frequency
- Detection rate
- Stream availability
- Tailscale connectivity

**Database:**
- Query performance
- Connection pool usage
- Replication lag
- Disk usage

### Tools

```
Prometheus: Metrics collection
Grafana: Dashboards
AlertManager: Alerting
Loki: Log aggregation
Jaeger: Distributed tracing (optional)
```

### Dashboard Example

```
┌────────────────────────────────────────┐
│ PlateBridge Operations Dashboard       │
├────────────────────────────────────────┤
│ Active PODs: 4,823 / 5,000            │
│ Offline PODs: 177                      │
│ Detections/min: 847                    │
│ API Latency: 45ms (p95)                │
│                                        │
│ [Graph: Detections over time]          │
│ [Graph: API response time]             │
│ [Map: POD locations]                   │
└────────────────────────────────────────┘
```

---

## Security at Scale

### Tailscale Benefits

1. **Zero-Trust by Default**
   - Every connection authenticated
   - No open ports to internet
   - ACLs enforce least privilege

2. **Key Rotation**
   ```bash
   # Rotate auth keys monthly
   tailscale logout
   tailscale up --authkey=$NEW_KEY
   ```

3. **Audit Logging**
   - All connections logged
   - Export to SIEM
   - Compliance ready

### Additional Security

```
- API rate limiting (Redis)
- DDoS protection (Cloudflare)
- WAF rules (Cloudflare or AWS)
- Secrets management (Vault or AWS Secrets Manager)
- Regular security audits
```

---

## Performance Optimization

### Video Streaming

**Direct POD → Browser:**
```
Latency: 50-200ms (direct)
Bandwidth: 2-5 Mbps per stream
Scalability: Unlimited (P2P-like)
```

**Via Portal Proxy:**
```
Latency: 200-500ms (double hop)
Bandwidth: Portal server bottleneck
Scalability: Limited by portal servers
```

**Recommendation:** Always stream direct when possible

### Caching Strategy

```
CDN (Cloudflare): Static assets (UI)
Redis: API responses, session data
Browser: Service worker for offline
Database: Materialized views for analytics
```

---

## Disaster Recovery

### Backup Strategy

```
Database:
- Hourly snapshots (keep 24 hours)
- Daily backups (keep 30 days)
- Weekly backups (keep 1 year)

Portal Configuration:
- Git repository (all configs)
- Terraform/IaC (infrastructure)

POD Recovery:
- Auto-provisioning script
- Config templates
- Automated Tailscale join
```

### Failover

```
Portal: Multi-region (active-active)
Database: Primary + replica (auto-failover)
PODs: Resilient by design (local caching)
```

---

## Summary

### Best Architecture for 1,000+ Communities

✅ **Self-Hosted Portal + Tailscale VPN**

**Why:**
- Scales to unlimited PODs
- Predictable costs ($0.10-0.20 per POD)
- Enterprise-grade security
- Direct video streaming
- Full control

**Cost:** $500-2,000/month (for 5,000-10,000 PODs)

**vs. Cloudflare Tunnel:** Save $50,000-300,000/year

---

## Next Steps

1. **Now:** Continue with Vercel + Cloudflare (Phase 1)
2. **At 50 PODs:** Test Tailscale migration (Phase 2)
3. **At 100 PODs:** Fully migrate to self-hosted (Phase 2)
4. **At 500 PODs:** Add regional servers (Phase 3)
5. **At 2,000 PODs:** Consider Kubernetes (Phase 4)

---

**Start simple, scale when needed!**

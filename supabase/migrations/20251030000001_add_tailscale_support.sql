/*
  # Add Tailscale Support to Pods

  1. Changes
    - Add `tailscale_ip` column to pods table for secure mesh networking
    - Add `tailscale_hostname` column for Tailscale device name
    - Update heartbeat to track Tailscale connectivity
    - Enable portal to connect directly to pods via Tailscale

  2. Benefits
    - Zero-trust secure communication
    - No port forwarding needed
    - Encrypted WireGuard tunnels
    - Direct pod-to-portal connectivity
*/

-- Add Tailscale columns to pods table
ALTER TABLE pods ADD COLUMN IF NOT EXISTS tailscale_ip TEXT;
ALTER TABLE pods ADD COLUMN IF NOT EXISTS tailscale_hostname TEXT;

-- Add index for quick Tailscale IP lookups
CREATE INDEX IF NOT EXISTS idx_pods_tailscale_ip ON pods(tailscale_ip);

-- Add comment for documentation
COMMENT ON COLUMN pods.tailscale_ip IS 'Tailscale mesh network IP (100.x.x.x) for secure pod connectivity';
COMMENT ON COLUMN pods.tailscale_hostname IS 'Tailscale device hostname for DNS resolution';

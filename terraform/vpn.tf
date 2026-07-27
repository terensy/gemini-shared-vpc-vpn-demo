# HA VPN,host <-> onprem,雙 tunnel + Cloud Router BGP。

resource "google_compute_ha_vpn_gateway" "host" {
  name    = "host-vpn-gateway"
  project = google_project.host.project_id
  region  = var.region
  network = google_compute_network.shared_vpc.id
}

resource "google_compute_ha_vpn_gateway" "onprem" {
  name    = "onprem-vpn-gateway"
  project = google_project.onprem.project_id
  region  = var.region
  network = google_compute_network.onprem_vpc.id
}

resource "google_compute_router" "host" {
  name    = "vpn-router"
  project = google_project.host.project_id
  region  = var.region
  network = google_compute_network.shared_vpc.name

  bgp {
    asn = 65001
  }
}

resource "google_compute_router" "onprem" {
  name    = "vpn-router"
  project = google_project.onprem.project_id
  region  = var.region
  network = google_compute_network.onprem_vpc.name

  bgp {
    asn = 65000
  }
}

resource "google_compute_vpn_tunnel" "host_tunnel_1" {
  name                  = "host-vpn-tunnel-1"
  project               = google_project.host.project_id
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.host.id
  vpn_gateway_interface = 0
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.onprem.id
  shared_secret         = var.vpn_tunnel_1_shared_secret
  router                = google_compute_router.host.id
  ike_version           = 2
}

resource "google_compute_vpn_tunnel" "host_tunnel_2" {
  name                  = "host-vpn-tunnel-2"
  project               = google_project.host.project_id
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.host.id
  vpn_gateway_interface = 1
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.onprem.id
  shared_secret         = var.vpn_tunnel_2_shared_secret
  router                = google_compute_router.host.id
  ike_version           = 2
}

resource "google_compute_vpn_tunnel" "onprem_tunnel_1" {
  name                  = "onprem-tunnel-1"
  project               = google_project.onprem.project_id
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.onprem.id
  vpn_gateway_interface = 0
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.host.id
  shared_secret         = var.vpn_tunnel_1_shared_secret
  router                = google_compute_router.onprem.id
  ike_version           = 2
}

resource "google_compute_vpn_tunnel" "onprem_tunnel_2" {
  name                  = "onprem-tunnel-2"
  project               = google_project.onprem.project_id
  region                = var.region
  vpn_gateway           = google_compute_ha_vpn_gateway.onprem.id
  vpn_gateway_interface = 1
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.host.id
  shared_secret         = var.vpn_tunnel_2_shared_secret
  router                = google_compute_router.onprem.id
  ike_version           = 2
}

# --- Host 端 Cloud Router interface + BGP peer ---

resource "google_compute_router_interface" "host_if_1" {
  name       = "if-host-bgp-session-1"
  project    = google_project.host.project_id
  region     = var.region
  router     = google_compute_router.host.name
  ip_range   = "169.254.222.97/30"
  vpn_tunnel = google_compute_vpn_tunnel.host_tunnel_1.name
}

resource "google_compute_router_interface" "host_if_2" {
  name       = "if-host-bgp-session-2"
  project    = google_project.host.project_id
  region     = var.region
  router     = google_compute_router.host.name
  ip_range   = "169.254.171.145/30"
  vpn_tunnel = google_compute_vpn_tunnel.host_tunnel_2.name
}

resource "google_compute_router_peer" "host_peer_1" {
  name            = "host-bgp-session-1"
  project         = google_project.host.project_id
  region          = var.region
  router          = google_compute_router.host.name
  interface       = google_compute_router_interface.host_if_1.name
  peer_ip_address = "169.254.222.98"
  peer_asn        = 65000

  bfd {
    min_receive_interval        = 1000
    min_transmit_interval       = 1000
    multiplier                  = 5
    session_initialization_mode = "DISABLED"
  }
}

resource "google_compute_router_peer" "host_peer_2" {
  name            = "host-bgp-session-2"
  project         = google_project.host.project_id
  region          = var.region
  router          = google_compute_router.host.name
  interface       = google_compute_router_interface.host_if_2.name
  peer_ip_address = "169.254.171.146"
  peer_asn        = 65000

  bfd {
    min_receive_interval        = 1000
    min_transmit_interval       = 1000
    multiplier                  = 5
    session_initialization_mode = "DISABLED"
  }
}

# --- Onprem 端 Cloud Router interface + BGP peer ---

resource "google_compute_router_interface" "onprem_if_1" {
  name       = "if-onprem-bgp-session-1"
  project    = google_project.onprem.project_id
  region     = var.region
  router     = google_compute_router.onprem.name
  ip_range   = "169.254.222.98/30"
  vpn_tunnel = google_compute_vpn_tunnel.onprem_tunnel_1.name
}

resource "google_compute_router_interface" "onprem_if_2" {
  name       = "if-onprem-bgp-session-2"
  project    = google_project.onprem.project_id
  region     = var.region
  router     = google_compute_router.onprem.name
  ip_range   = "169.254.171.146/30"
  vpn_tunnel = google_compute_vpn_tunnel.onprem_tunnel_2.name
}

resource "google_compute_router_peer" "onprem_peer_1" {
  name            = "onprem-bgp-session-1"
  project         = google_project.onprem.project_id
  region          = var.region
  router          = google_compute_router.onprem.name
  interface       = google_compute_router_interface.onprem_if_1.name
  peer_ip_address = "169.254.222.97"
  peer_asn        = 65001

  bfd {
    min_receive_interval        = 1000
    min_transmit_interval       = 1000
    multiplier                  = 5
    session_initialization_mode = "DISABLED"
  }
}

resource "google_compute_router_peer" "onprem_peer_2" {
  name            = "onprem-bgp-session-2"
  project         = google_project.onprem.project_id
  region          = var.region
  router          = google_compute_router.onprem.name
  interface       = google_compute_router_interface.onprem_if_2.name
  peer_ip_address = "169.254.171.145"
  peer_asn        = 65001

  bfd {
    min_receive_interval        = 1000
    min_transmit_interval       = 1000
    multiplier                  = 5
    session_initialization_mode = "DISABLED"
  }
}

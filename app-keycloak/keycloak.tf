terraform {
  required_providers {
    keycloak = {
      source  = "mrparkers/keycloak"
      version = "3.6.0"
    }
  }
}
# configure keycloak provider
provider "keycloak" {
  client_id                = "admin-cli"
  username                 = "admin"
  password                 = "admin"
  url                      = "https://keycloak.dedalus"
  tls_insecure_skip_verify = true
  base_path                = ""
}
locals {
  realm_id = "dedalus"
  groups   = ["kubeappsadmin", "kubeappsdeployer"]
  user_groups = {
    user-admin   = ["kubeappsadmin"]
    user-deployer = ["kubeappsdeployer"]
  }
}
# Create Realm
resource "keycloak_realm" "dedalus_realm" {
  realm             = local.realm_id
  enabled           = true
  display_name      = "Dedalus"
  display_name_html = "<b>Dedalus</b>"

  login_theme = "base"

  access_code_lifespan = "1h"

  ssl_required    = "external"
#  password_policy = "upperCase(1) and length(8) and forceExpiredPasswordChange(365)"
  attributes      = {
    mycustomAttribute = "myCustomValue"
  }

  internationalization {
    supported_locales = [
      "en",
      "it"
    ]
    default_locale    = "en"
  }
}

# create groups
resource "keycloak_group" "groups" {
  for_each = toset(local.groups)
  realm_id = keycloak_realm.dedalus_realm.id
  name     = each.key
}
# create users
resource "keycloak_user" "users" {
  for_each       = local.user_groups
  realm_id       = keycloak_realm.dedalus_realm.id
  username       = each.key
  enabled        = true
  email          = "${each.key}@domain.com"
  email_verified = true
  first_name     = each.key
  last_name      = each.key
  initial_password {
    value = each.key
  }
}
# configure use groups membership
resource "keycloak_user_groups" "user_groups" {
  for_each  = local.user_groups
  realm_id  = keycloak_realm.dedalus_realm.id
  user_id   = keycloak_user.users[each.key].id
  group_ids = [for g in each.value : keycloak_group.groups[g].id]
}
# create groups openid client scope
resource "keycloak_openid_client_scope" "groups" {
  realm_id               = keycloak_realm.dedalus_realm.id
  name                   = "groups"
  include_in_token_scope = true
  gui_order              = 1
}
resource "keycloak_openid_group_membership_protocol_mapper" "groups" {
  realm_id        = keycloak_realm.dedalus_realm.id
  client_scope_id = keycloak_openid_client_scope.groups.id
  name            = "groups"
  claim_name      = "groups"
  full_path       = false
}
# create kube openid client
resource "keycloak_openid_client" "kubeapps" {
  realm_id                     = keycloak_realm.dedalus_realm.id
  client_id                    = "kubeapps"
  name                         = "kubeapps"
  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  client_secret                = "kubeapps-secret"
  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  valid_redirect_uris = [
    "https://kubeapps.dedalus/oauth2/callback"
  ]
}
# configure kube openid client default scopes
resource "keycloak_openid_client_default_scopes" "kubeapps" {
  realm_id  = keycloak_realm.dedalus_realm.id
  client_id = keycloak_openid_client.kubeapps.id
  default_scopes = [
    "email",
    keycloak_openid_client_scope.groups.name,
  ]
}

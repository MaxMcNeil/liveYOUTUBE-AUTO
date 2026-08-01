variable "region" {
  description = "Région OCI"
  type        = string
  default     = "eu-turin-1"
}

variable "compartment_ocid" {
  description = "OCID du compartiment (par défaut : compartiment racine = OCID du tenancy)"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Chemin local vers votre clé publique SSH (ex: ~/.ssh/id_ed25519.pub)"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Chemin local vers votre clé privée SSH correspondante, utilisée par Terraform pour se connecter et déployer"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "Plage IP autorisée à se connecter en SSH (mettez VOTRE IP publique /32, pas 0.0.0.0/0)"
  type        = string
}

variable "instance_ocpus" {
  description = "Nombre d'OCPU (ARM Ampere A1 — jusqu'à 4 OCPU/24 Go gratuits en Always Free)"
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Mémoire en Go"
  type        = number
  default     = 12
}

variable "youtube_stream_key" {
  description = "Clé de stream YouTube (rtmp), depuis YouTube Studio > Diffuser en direct"
  type        = string
  sensitive   = true
}

variable "youtube_stream_id" {
  description = "Optionnel — ID du flux persistant YouTube, pour l'automatisation du titre/description quotidiens (laisser vide pour désactiver)"
  type        = string
  default     = ""
}

variable "google_client_id" {
  description = "Optionnel — Client OAuth Google (voir README.md, section Automatisation YouTube)"
  type        = string
  default     = ""
}

variable "google_client_secret" {
  description = "Optionnel — Secret OAuth Google"
  type        = string
  default     = ""
  sensitive   = true
}

variable "google_refresh_token" {
  description = "Optionnel — Refresh token obtenu via get_refresh_token.js (exécuté en local, une seule fois)"
  type        = string
  default     = ""
  sensitive   = true
}

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

variable "instance_shape" {
  description = "Shape de l'instance. Confirmé disponible par le support Oracle : VM.Standard.A1.Flex, 2 OCPU (Always Free). Alternative si indisponible : VM.Standard.E2.1.Micro (fixe, pas de shape_config) ou un shape payant comme VM.Standard.E4.Flex."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "OCPU — utilisé uniquement si instance_shape est un shape *.Flex"
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Mémoire en Go — utilisé uniquement si instance_shape est un shape *.Flex"
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

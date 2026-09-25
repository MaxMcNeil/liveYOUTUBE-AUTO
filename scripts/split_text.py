#!/usr/bin/env python3
"""
Découpe un texte long en N morceaux, eux-mêmes composés d'une liste
d'énoncés courts (phrases, ou sous-clauses si une phrase est trop
longue). Chaque énoncé sera généré par un appel Chatterbox SÉPARÉ, puis
recollé avec un petit silence — c'est ce qui rend le clonage robuste :
un modèle autorégressif comme Chatterbox dérive/hallucine bien plus sur
un gros pavé de texte que sur des phrases courtes prises une par une.

Algorithme volontairement simple et déterministe : le même texte + le
même N produisent toujours exactement le même résultat, peu importe la
machine qui l'exécute — essentiel car chaque job du matrix GitHub
Actions relance ce script indépendamment.

Format de sortie (chunks.json) :
    [
      [ [texte, pause_ms_apres, exaggeration, cfg_weight], ... ],  # chunk 0
      [ ... ],  # chunk 1
      ...
    ]

Usage :
    python3 split_text.py texte.txt --chunks 20 --out chunks.json

Balises de ton optionnelles dans le texte source : [ton:normal],
[ton:calme], [ton:colere], [ton:sarcastique] — voir TONE_PRESETS
ci-dessous pour le détail et les limites.
"""
import argparse
import json
import re
import sys

# Découpage en phrases : on coupe après ".", "!", "?" ou "…" suivi d'un
# espace/saut de ligne. Reste volontairement simple (pas de gestion fine
# des abréviations type "M." ou "etc.") — un léger sur-découpage à ces
# endroits n'est pas grave, la contrainte dure est juste de ne jamais
# couper EN PLEIN MILIEU d'une phrase.
# Découpage en phrases : on coupe après "." "!" ou "?" suivi d'un
# espace/saut de ligne. Le "…" n'en fait volontairement PAS partie : il
# sert souvent de pause DANS une phrase ("Premièrement… la remise..."),
# pas de fin de phrase — le laisser dans le texte de l'énoncé permet à
# Chatterbox de restituer cette pause naturellement en un seul appel,
# plutôt que de forcer un énoncé isolé d'un ou deux mots. Reste
# volontairement simple par ailleurs (pas de gestion fine des
# abréviations type "M." ou "etc.") — un léger sur-découpage à ces
# endroits n'est pas grave, la contrainte dure est juste de ne jamais
# couper EN PLEIN MILIEU d'une phrase.
SENTENCE_SPLIT_RE = re.compile(r"(?<=[.!?])\s+")

# Une phrase individuelle plus longue que ça est encore sous-découpée à
# une frontière de clause (virgule, point-virgule, deux-points, tiret) —
# les phrases-fleuves sont justement ce qui fait le plus dériver
# Chatterbox. Chaque appel Chatterbox reste ainsi toujours court.
MAX_CHARS_PER_UTTERANCE = 220

# Un "chunk" (= un fichier audio final, une des coupures pendant le
# live) regroupe plusieurs phrases. Ce plafond ne sert plus qu'à la
# granularité de programmation du live (nombre de coupures) — il n'y a
# plus de risque de troncature Chatterbox ici puisque chaque phrase est
# générée séparément.
MAX_CHARS_PER_CHUNK = 1000

PAUSE_SENTENCE_MS = 380  # entre deux phrases réelles (respiration naturelle)
PAUSE_CLAUSE_MS = 150    # entre deux sous-clauses d'une même phrase trop longue

CLAUSE_SPLIT_RE = re.compile(r"(?<=[,;:—–…])\s+")

# Balises optionnelles dans le texte source : [ton:normal], [ton:colere],
# [ton:calme], [ton:sarcastique]. Change le ton à partir de cet endroit
# jusqu'à la balise suivante (ou la fin du texte). Rien à mettre si tu
# ne veux pas t'en servir — tout reste en "normal" par défaut.
#
# Chatterbox n'a pas de sélecteur d'émotions nommées ("colère",
# "joie"...) — seulement deux curseurs : exaggeration (intensité
# émotionnelle, 0=plat, 0.5=naturel, 1.5-2=théâtral) et cfg_weight
# (rythme — plus bas = plus lent/appuyé, compense une exaggeration
# élevée qui accélère sinon le débit). Ces profils sont une
# approximation à base de ces 2 curseurs, pas un vrai moteur d'émotions.
# NB : le sarcasme n'est PAS fiable avec ce type de réglage — l'ironie
# tient surtout au choix des mots, pas à un paramètre audio. Le profil
# "sarcastique" ci-dessous reste expérimental.
TONE_PRESETS = {
    "normal":      {"exaggeration": 0.5, "cfg_weight": 0.5},
    "calme":       {"exaggeration": 0.3, "cfg_weight": 0.6},
    "colere":      {"exaggeration": 0.9, "cfg_weight": 0.35},
    "sarcastique": {"exaggeration": 0.6, "cfg_weight": 0.4},  # expérimental
}
DEFAULT_TONE = "normal"
TONE_TAG_RE = re.compile(r"\[ton:(\w+)\]", re.IGNORECASE)


def split_into_toned_segments(text: str):
    """Découpe le texte aux balises [ton:xxx], renvoie une liste de
    (texte_segment, nom_du_ton). Le texte AVANT la première balise est
    en ton par défaut. Une balise avec un nom inconnu déclenche une
    erreur claire plutôt qu'un échec silencieux."""
    segments = []
    current_tone = DEFAULT_TONE
    pos = 0
    for m in TONE_TAG_RE.finditer(text):
        before = text[pos:m.start()]
        if before.strip():
            segments.append((before, current_tone))
        tone_name = m.group(1).lower()
        if tone_name not in TONE_PRESETS:
            print(
                f"ERREUR : ton inconnu '[ton:{tone_name}]' dans le texte. "
                f"Tons disponibles : {', '.join(TONE_PRESETS)}.",
                file=sys.stderr,
            )
            sys.exit(1)
        current_tone = tone_name
        pos = m.end()
    tail = text[pos:]
    if tail.strip():
        segments.append((tail, current_tone))
    return segments


def normalize_punctuation(text: str) -> str:
    # "Alors !!!!" -> "Alors !" : la ponctuation répétée n'apporte rien
    # à un moteur TTS et peut perturber la génération.
    text = re.sub(r"([!?])\1+", r"\1", text)
    # "..." (points de suspension tapés à la main) -> "…" (un seul
    # caractère, déjà géré comme frontière de phrase ci-dessus).
    text = re.sub(r"\.{3,}", "…", text)
    return text


def split_sentences(text: str):
    text = normalize_punctuation(text.strip())
    if not text:
        return []
    # Normalise les espaces multiples/retours à la ligne à l'intérieur
    # d'un paragraphe pour ne pas fausser le comptage de caractères,
    # mais garde les paragraphes comme des frontières de phrase fortes.
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    sentences = []
    for para in paragraphs:
        para = re.sub(r"\s+", " ", para)
        parts = SENTENCE_SPLIT_RE.split(para)
        sentences.extend(s.strip() for s in parts if s.strip())
    return sentences


def split_long_sentence(sentence: str, tone: str, max_len: int = MAX_CHARS_PER_UTTERANCE):
    """Renvoie une liste de (texte, pause_ms_apres, ton) pour UNE phrase.

    Si la phrase tient sous max_len, un seul élément avec une pause
    "fin de phrase". Sinon, découpe à des frontières de clause
    (virgule, point-virgule, ...) en énoncés plus courts, chacun avec
    une pause plus brève, sauf le dernier qui garde la pause "fin de
    phrase" puisque c'est bien la fin de la phrase d'origine. Le ton
    est le même pour toutes les sous-clauses d'une même phrase.
    """
    if len(sentence) <= max_len:
        return [(sentence, PAUSE_SENTENCE_MS, tone)]

    clauses = [c.strip() for c in CLAUSE_SPLIT_RE.split(sentence) if c.strip()]
    if len(clauses) <= 1:
        # Pas de virgule/ponctuation interne pour s'accrocher : dernier
        # recours, on coupe brutalement à des frontières de mots.
        words = sentence.split(" ")
        clauses = []
        current = ""
        for w in words:
            if current and len(current) + 1 + len(w) > max_len:
                clauses.append(current)
                current = w
            else:
                current = f"{current} {w}".strip()
        if current:
            clauses.append(current)

    # Regroupe les clauses consécutives tant que ça tient sous max_len,
    # pour éviter de sur-découper inutilement une phrase à la limite.
    packed = []
    current = ""
    for clause in clauses:
        candidate = f"{current}, {clause}".strip(", ").strip() if current else clause
        if current and len(candidate) > max_len:
            packed.append(current)
            current = clause
        else:
            current = candidate
    if current:
        packed.append(current)

    return [(c, PAUSE_CLAUSE_MS, tone) for c in packed[:-1]] + [(packed[-1], PAUSE_SENTENCE_MS, tone)]


def pack_into_chunks(toned_sentences, n_chunks: int, hard_max_chars: int = MAX_CHARS_PER_CHUNK):
    """toned_sentences : liste de (texte_phrase, ton)."""
    total_chars = sum(len(s) for s, _ in toned_sentences)
    if total_chars == 0:
        return []
    target = total_chars / n_chunks
    soft_limit = min(target * 1.15, hard_max_chars)

    chunk_sentence_groups = []
    current = []
    current_len = 0
    for sentence, tone in toned_sentences:
        if current and (current_len + len(sentence)) > soft_limit:
            chunk_sentence_groups.append(current)
            current = []
            current_len = 0
        current.append((sentence, tone))
        current_len += len(sentence) + 1
    if current:
        chunk_sentence_groups.append(current)

    # Chaque chunk devient une liste d'énoncés (phrase entière, ou
    # sous-clauses si trop longue), chacun avec sa pause et son ton.
    chunks = []
    for group in chunk_sentence_groups:
        utterances = []
        for sentence, tone in group:
            utterances.extend(split_long_sentence(sentence, tone))
        chunks.append(utterances)

    return chunks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("text_file", help="Fichier texte source (UTF-8)")
    ap.add_argument("--chunks", type=int, required=True, help="Nombre de morceaux visé (minimum)")
    ap.add_argument("--out", required=True, help="Fichier JSON de sortie")
    args = ap.parse_args()

    with open(args.text_file, "r", encoding="utf-8") as f:
        text = f.read()

    toned_sentences = []
    for segment_text, tone in split_into_toned_segments(text):
        for sentence in split_sentences(segment_text):
            toned_sentences.append((sentence, tone))

    if not toned_sentences:
        print("ERREUR : le texte est vide après nettoyage.", file=sys.stderr)
        sys.exit(1)

    n_chunks = min(args.chunks, len(toned_sentences))
    if n_chunks < args.chunks:
        print(
            f"[split_text] Attention : seulement {len(toned_sentences)} phrases détectées, "
            f"impossible de faire {args.chunks} morceaux distincts. "
            f"Réduit automatiquement à {n_chunks}.",
            file=sys.stderr,
        )

    total_chars = sum(len(s) for s, _ in toned_sentences)
    min_chunks_for_granularity = max(1, -(-total_chars // MAX_CHARS_PER_CHUNK))  # ceil division
    if min_chunks_for_granularity > n_chunks:
        print(
            f"[split_text] Nombre de morceaux augmenté automatiquement de {n_chunks} à "
            f"{min_chunks_for_granularity} (pour garder des coupures raisonnablement "
            f"espacées pendant le live).",
            file=sys.stderr,
        )
        n_chunks = min_chunks_for_granularity

    chunks = pack_into_chunks(toned_sentences, n_chunks)

    # Résout le nom du ton en (exaggeration, cfg_weight) pour le JSON de
    # sortie — generate_voice_chunk.py n'a ainsi rien à connaître des
    # tons, juste les 2 valeurs numériques à passer à Chatterbox.
    resolved_chunks = []
    for chunk in chunks:
        resolved = []
        for text_u, pause_ms, tone in chunk:
            preset = TONE_PRESETS[tone]
            resolved.append([text_u, pause_ms, preset["exaggeration"], preset["cfg_weight"]])
        resolved_chunks.append(resolved)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(resolved_chunks, f, ensure_ascii=False, indent=2)

    total_utterances = sum(len(c) for c in resolved_chunks)
    print(f"[split_text] {len(resolved_chunks)} morceau(x) / {total_utterances} énoncé(s) au "
          f"total écrits dans {args.out}")
    for i, c in enumerate(resolved_chunks):
        chars = sum(len(u[0]) for u in c)
        preview = c[0][0][:50] if c else ""
        print(f"  [{i:03d}] {len(c)} énoncé(s), {chars} caractères — \"{preview}...\"")


if __name__ == "__main__":
    main()

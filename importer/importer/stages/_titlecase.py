"""Smart title-casing for all-caps source labels (importer-feedback issue 5).

Only the normalize stage calls this, and only for names with no lowercase letter
(see normalize.py) — already-mixed-case names are assumed well-cased and left
untouched. The preserve-list is curated and maintained: add acronyms as new
sources surface them.
"""

from __future__ import annotations

import re

# 2-letter USPS codes that are ALSO common English words: title-case them
# normally (Building In Tampa) rather than shouting them (Building IN Tampa).
_AMBIGUOUS_STATE_CODES = {"IN", "OR", "OK", "ME", "HI", "OH", "ID"}

_STATE_CODES = {
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "IA", "IL",
    "KS", "KY", "LA", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV",
    "NH", "NJ", "NM", "NY", "NC", "ND", "PA", "RI", "SC", "SD", "TN", "TX",
    "UT", "VT", "VA", "WA", "WV", "WI", "WY", "DC",
} - _AMBIGUOUS_STATE_CODES

# Federal agencies / common government acronyms seen in GSA/HIFLD/FAA labels.
_FEDERAL_ACRONYMS = {
    "US", "USA", "VA", "SBA", "FBI", "IRS", "FAA", "GSA", "DOD", "USACE",
    "NFH", "USCG", "TSA", "DHS", "FEMA", "ATF", "DEA", "EPA", "NOAA", "NASA",
    "USDA", "DOI", "DOJ", "DOT", "HHS", "HUD", "NPS", "USFS", "BLM", "USGS",
    "NIH", "CDC", "FDA", "SSA", "USPS", "NWS", "USAF", "USMC",
}

_PRESERVE: frozenset[str] = frozenset(_STATE_CODES | _FEDERAL_ACRONYMS)

_ROMAN_RE = re.compile(r"^M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$")
_ORDINAL_RE = re.compile(r"^\d+(ST|ND|RD|TH)$", re.IGNORECASE)


def _capitalize(word: str) -> str:
    return word[:1].upper() + word[1:].lower() if word else word


def _case_token(token: str) -> str:
    if not token:
        return token
    upper = token.upper()
    if upper in _PRESERVE:
        return upper
    if len(token) > 1 and _ROMAN_RE.match(upper):
        return upper
    if _ORDINAL_RE.match(token):
        return token.lower()
    if "-" in token:
        return "-".join(_case_token(p) for p in token.split("-"))
    if "'" in token:
        return "'".join(_capitalize(p) for p in token.split("'"))
    if upper.startswith("MC") and len(token) > 2:
        return "Mc" + _capitalize(token[2:])
    return _capitalize(token)


def smart_title_case(name: str) -> str:
    return " ".join(_case_token(tok) for tok in name.split(" "))

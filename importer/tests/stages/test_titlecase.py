from importer.stages._titlecase import smart_title_case


def test_basic_all_caps_to_title():
    assert smart_title_case("UNITED STATES COURTHOUSE") == "United States Courthouse"


def test_preserves_trailing_state_code():
    assert smart_title_case("OFFICE BUILDING TAMPA FL") == "Office Building Tampa FL"


def test_preserves_federal_acronyms():
    assert smart_title_case("US ARMY CORPS USACE DEPOT") == "US Army Corps USACE Depot"


def test_ambiguous_state_codes_are_not_uppercase_preserved():
    # IN/OR are also English words; title-case them rather than shouting them.
    assert smart_title_case("BUILDING IN TAMPA") == "Building In Tampa"
    assert smart_title_case("PARK OR LOT") == "Park Or Lot"


def test_mc_and_apostrophe_names():
    assert smart_title_case("MCDONALD HALL") == "McDonald Hall"
    assert smart_title_case("O'BRIEN CENTER") == "O'Brien Center"


def test_hyphen_and_roman_numerals():
    assert smart_title_case("WINSTON-SALEM CENTER III") == "Winston-Salem Center III"


def test_ordinals_lowercased():
    assert smart_title_case("1ST AVENUE BUILDING") == "1st Avenue Building"

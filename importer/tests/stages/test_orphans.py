from pathlib import Path

import pytest

from importer.geo.states import load_state_locator
from importer.stages.orphans import (
    OrphanPlan,
    default_cap,
    plan_orphans,
    scope_to_states,
)
from importer.supabase_client import ExistingPinRow

LOCATOR = load_state_locator(Path(__file__).parents[1] / "fixtures" / "states_sample.geojson")
AUSTIN, MIAMI, NULL_ISLAND = (30.27, -97.74), (25.77, -80.19), (0.5, 0.5)


def _pin(pid, at=AUSTIN, *, user_modified=False):
    return ExistingPinRow(
        id=pid, source="gsa", source_external_id=f"E-{pid}", name=pid,
        latitude=at[0], longitude=at[1], status=2, restriction_tag="FEDERAL_PROPERTY",
        user_modified=user_modified, source_dataset_version="v",
    )


@pytest.mark.parametrize("in_scope, cap", [(0, 50), (1000, 50), (1019, 50), (4221, 211), (20000, 1000)])
def test_default_cap_is_50_or_5_percent(in_scope, cap):
    assert default_cap(in_scope) == cap


def test_mark_mode_marks_every_orphan_and_never_breaches():
    orphans = [_pin(f"p{i}") for i in range(500)]
    plan = plan_orphans(orphans, in_scope_count=500, delete=False)
    assert plan.mark == orphans and plan.delete == [] and plan.keep == []
    assert not plan.breached
    assert plan.marked_count == 500


def test_delete_mode_keeps_user_corrected_pins():
    gone, fixed = _pin("gone"), _pin("fixed", user_modified=True)
    plan = plan_orphans([gone, fixed], in_scope_count=10, delete=True)
    assert plan.delete == [gone] and plan.keep == [fixed] and plan.mark == []
    assert plan.marked_count == 1
    assert plan.actions() == [(gone, "delete"), (fixed, "keep")]


def test_cap_breaches_only_past_the_cap():
    at_cap = plan_orphans([_pin(f"p{i}") for i in range(50)], in_scope_count=100, delete=True)
    assert at_cap.cap == 50 and not at_cap.breached
    over = plan_orphans([_pin(f"p{i}") for i in range(51)], in_scope_count=100, delete=True)
    assert over.breached


def test_cap_override_replaces_the_default():
    plan = plan_orphans([_pin(f"p{i}") for i in range(51)], in_scope_count=100, delete=True, cap=100)
    assert plan.cap == 100 and not plan.breached


def test_empty_plan_is_the_default():
    assert OrphanPlan().marked_count == 0 and not OrphanPlan().breached


def test_scope_keeps_only_pins_in_the_run_states():
    tx, fl = _pin("tx", AUSTIN), _pin("fl", MIAMI)
    assert scope_to_states([tx, fl], states={"TX"}, locator=LOCATOR) == [tx]
    assert scope_to_states([tx, fl], states=None, locator=None) == [tx, fl]


def test_pin_outside_every_state_is_never_in_scope():
    stray = _pin("stray", NULL_ISLAND)
    assert scope_to_states([stray], states={"TX", "FL", "PA"}, locator=LOCATOR) == []


def test_scoping_by_state_needs_a_locator():
    assert scope_to_states([], states={"TX"}, locator=None) == []
    with pytest.raises(ValueError, match="state_locator"):
        scope_to_states([_pin("tx")], states={"TX"}, locator=None)

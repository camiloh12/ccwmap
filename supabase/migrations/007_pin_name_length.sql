-- 007_pin_name_length.sql
-- Cap the pin name at 60 characters. The client also enforces this via
-- TextField(maxLength: 60), but we want the server to reject longer names
-- defensively so manual API callers can't inject long content.
-- Runs only if no row currently violates the constraint -- Step 2 of the
-- plan verifies this before the migration is applied.

ALTER TABLE pins
  ADD CONSTRAINT pins_name_length_check
  CHECK (char_length(name) <= 60);

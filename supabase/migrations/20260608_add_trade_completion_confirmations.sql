-- Require each side of a social trade to confirm completion independently.
ALTER TABLE trades
  ADD COLUMN IF NOT EXISTS initiator_completed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS receiver_completed BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_trades_completion_confirmations
  ON trades(status, initiator_completed, receiver_completed);

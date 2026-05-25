-- Create trade_sessions table for mutual QR trading (in-person trade show flow)
CREATE TABLE IF NOT EXISTS trade_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  initiator_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  participant_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'open',
  initiator_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  participant_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  initiator_offer_submitted BOOLEAN NOT NULL DEFAULT false,
  participant_offer_submitted BOOLEAN NOT NULL DEFAULT false,
  initiator_accepted BOOLEAN NOT NULL DEFAULT false,
  participant_accepted BOOLEAN NOT NULL DEFAULT false,
  execution_lock UUID,
  trade_record_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS
ALTER TABLE trade_sessions ENABLE ROW LEVEL SECURITY;

-- Policies: only initiator and participant can see/update their session
CREATE POLICY "Users can view their own trade sessions"
  ON trade_sessions FOR SELECT
  USING (initiator_id = auth.uid() OR participant_id = auth.uid());

CREATE POLICY "Users can create trade sessions"
  ON trade_sessions FOR INSERT
  WITH CHECK (initiator_id = auth.uid());

CREATE POLICY "Users can update their trade sessions"
  ON trade_sessions FOR UPDATE
  USING (initiator_id = auth.uid() OR participant_id = auth.uid());

-- Indexes
CREATE INDEX IF NOT EXISTS idx_trade_sessions_initiator ON trade_sessions(initiator_id);
CREATE INDEX IF NOT EXISTS idx_trade_sessions_participant ON trade_sessions(participant_id);
CREATE INDEX IF NOT EXISTS idx_trade_sessions_status ON trade_sessions(status);

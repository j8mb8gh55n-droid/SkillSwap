-- Review and rehearse in staging before applying.
BEGIN;

SET LOCAL lock_timeout = '5s';

-- Index creation fails and rolls back if any pending pair is duplicated.
CREATE UNIQUE INDEX exchanges_one_pending_per_pair_idx
    ON public.exchanges (requester_id, recipient_id)
    WHERE status = 'pending';

COMMIT;

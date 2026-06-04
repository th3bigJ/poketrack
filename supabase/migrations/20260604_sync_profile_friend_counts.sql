-- Keep profile friend counts derived from accepted friendship rows.
-- This repairs existing stale counts and prevents future drift when requests
-- are accepted, deleted, or blocked.

CREATE OR REPLACE FUNCTION public.recalculate_profile_friend_count(profile_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles
  SET friend_count = (
    SELECT COUNT(*)::int
    FROM public.friendships
    WHERE status = 'accepted'
      AND (requester_id = profile_id OR addressee_id = profile_id)
  )
  WHERE id = profile_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.recalculate_friendship_profile_counts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.recalculate_profile_friend_count(NEW.requester_id);
    PERFORM public.recalculate_profile_friend_count(NEW.addressee_id);
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    PERFORM public.recalculate_profile_friend_count(OLD.requester_id);
    PERFORM public.recalculate_profile_friend_count(OLD.addressee_id);
    PERFORM public.recalculate_profile_friend_count(NEW.requester_id);
    PERFORM public.recalculate_profile_friend_count(NEW.addressee_id);
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    PERFORM public.recalculate_profile_friend_count(OLD.requester_id);
    PERFORM public.recalculate_profile_friend_count(OLD.addressee_id);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS recalculate_friendship_profile_counts_trigger ON public.friendships;
CREATE TRIGGER recalculate_friendship_profile_counts_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.friendships
FOR EACH ROW
EXECUTE FUNCTION public.recalculate_friendship_profile_counts();

CREATE OR REPLACE FUNCTION public.get_profile_friend_counts(user_ids UUID[])
RETURNS TABLE(user_id UUID, friend_count int)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH requested_users AS (
    SELECT DISTINCT unnest(user_ids) AS user_id
  ),
  accepted_friendships AS (
    SELECT requester_id AS user_id
    FROM public.friendships
    WHERE status = 'accepted'
    UNION ALL
    SELECT addressee_id AS user_id
    FROM public.friendships
    WHERE status = 'accepted'
  )
  SELECT requested_users.user_id, COALESCE(COUNT(accepted_friendships.user_id), 0)::int AS friend_count
  FROM requested_users
  LEFT JOIN accepted_friendships ON accepted_friendships.user_id = requested_users.user_id
  GROUP BY requested_users.user_id;
$$;

UPDATE public.profiles p
SET friend_count = COALESCE(counts.friend_count, 0)
FROM (
  SELECT user_id, COUNT(*)::int AS friend_count
  FROM (
    SELECT requester_id AS user_id
    FROM public.friendships
    WHERE status = 'accepted'
    UNION ALL
    SELECT addressee_id AS user_id
    FROM public.friendships
    WHERE status = 'accepted'
  ) accepted_friendships
  GROUP BY user_id
) counts
WHERE p.id = counts.user_id;

UPDATE public.profiles p
SET friend_count = 0
WHERE NOT EXISTS (
  SELECT 1
  FROM public.friendships f
  WHERE f.status = 'accepted'
    AND (f.requester_id = p.id OR f.addressee_id = p.id)
);

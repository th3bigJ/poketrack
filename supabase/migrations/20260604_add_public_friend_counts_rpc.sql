-- Expose aggregate friend counts without exposing other users' friendship rows.
-- Safe to apply after the friend-count trigger migration; also repairs counts again.

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

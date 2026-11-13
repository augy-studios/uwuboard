-- 0003 · Make the image buckets private
--
-- Card images and avatars are served through the API now (api/images/get.js and
-- api/auth/avatar.js read them with the service role key), so neither bucket needs to be
-- public. After this, the public URLs handed out before stop working for everyone: board
-- files exported before images were hidden import without their pictures, and anything
-- outside uwuBoard that shows these URLs (another app showing an avatar, say) stops showing
-- them.
--
-- Safe to run more than once.

update storage.buckets
set public = false
where id in ('card-images', 'avatars');

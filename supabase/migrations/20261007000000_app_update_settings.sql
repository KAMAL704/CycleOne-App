-- Public release metadata used by the mandatory update screen.
-- Keep the values equal to the currently shipped APK until a new APK is ready.
insert into public.settings (key, value) values
  ('latest_version', '1.0.0'),
  ('latest_build_number', '1'),
  ('android_apk_url', ''),
  ('update_required', 'true'),
  ('update_title', 'CycleOne update available'),
  ('update_notes', 'Install the latest CycleOne APK to continue.')
on conflict (key) do nothing;

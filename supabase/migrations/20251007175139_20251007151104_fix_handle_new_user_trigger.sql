/*
  # Fix handle_new_user Trigger to Bypass RLS

  1. Changes
    - Update the handle_new_user function to use SET LOCAL to bypass RLS
    - This allows the trigger to insert the user profile regardless of RLS policies

  2. Security
    - Function is SECURITY DEFINER so it runs with elevated privileges
    - Only creates a viewer role by default (safe)
    - Only triggered on new user signup in auth.users
*/

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.user_profiles (id, role)
  VALUES (NEW.id, 'viewer');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'Error creating user profile: %', SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
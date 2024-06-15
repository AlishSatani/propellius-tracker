create function app_private.assert_valid_password(new_password text) returns void as $$
begin
  if length(new_password) < 8 then
    raise exception 'Password is too weak' using errcode = 'WEAKP';
  end if;
end;
$$ language plpgsql volatile;

create function app_private.really_create_user(
  username citext,
  email citext,
  password text default null
) returns app_public.users as $$
declare
  v_user app_public.users;
  v_username citext = username;
  v_email citext = email;
begin
  if v_username is null or password is null then
    raise exception 'Must provide valid username and password.' using errcode='INVLD';
  end if;

  perform app_private.assert_valid_password(password);

  v_username = regexp_replace(v_username, '^[^a-z]+', '', 'gi');
  v_username = regexp_replace(v_username, '[^a-z0-9]+', '_', 'gi');

  if exists(select 1 from app_public.users where users.username = v_username or users.email = v_email) then
    raise exception 'An account using that username or email has already been created.' using errcode='UMTKN';
  end if;

  insert into app_public.users (username, email)
  values (v_username, v_email)
    returning * into v_user;

  update app_private.user_secrets
  set password_hash = crypt(password, gen_salt('bf'))
  where user_id = v_user.id;

  select * into v_user from app_public.users where id = v_user.id;

  return v_user;
end;
$$ language plpgsql volatile;

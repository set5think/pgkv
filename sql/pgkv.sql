-- create keyval schema for all key/value types (strings, numbers, hashes, arrays)
create schema keyval;

-- create the key/value table for strings
create unlogged table keyval.strings (
  key varchar primary key,
  value text,
  created_at timestamp,
  updated_at timestamp
);

-- create the key/value table for numbers
create unlogged table keyval.numbers (
  key varchar primary key,
  value int not null default 0,
  created_at timestamp,
  updated_at timestamp
);

-- create the key/value table for hashes
create extension hstore;

create unlogged table keyval.hashes (
  key varchar primary key,
  value hstore,
  created_at timestamp,
  updated_at timestamp
);

-- KVAPPEND: Appends the value to the end of the string if the key has already been set.
--           If the key does not exist, sets the key to hold the string value instead.
--           The length of the current string value is always returned.
--  ARG1: keyname varchar
--  ARG2: valuestring text
--  RTRN: integer
--
-- EXAMPLE 1:
--  select * from kvappend('abc', 'hello');
--   kvappend
--  ----------
--          5
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvappend('abc', 'world');
--   kvappend
--  ----------
--         10
--  (1 row)
create or replace function kvappend(keyname varchar, valuestring text) returns int as $$
declare
  result int;
begin
  update keyval.strings set value = (value || valuestring), updated_at = now() where key = keyname returning char_length(value) into result;
  if not found then
    insert into keyval.strings (key, value, created_at, updated_at) values (keyname, valuestring, now(), now());
    result := char_length(valuestring);
  end if;
  return result;
end;
$$ language 'plpgsql';

-- KVDEL: Deletes the string value held by the key and returns TRUE.
--        If the key does not exist, FALSE is returned instead.
--  ARG1: keyname varchar
--  RTRN: boolean
--
-- EXAMPLE 1:
--  select * from kvdel('abc');
--   kvdel
--  -------
--   t
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvdel('nonexistent');
--
--   kvdel
--  -------
--   f
--  (1 row)
create or replace function kvdel(keyname varchar) returns boolean as $$
declare
  result boolean := false;
begin
  delete from keyval.strings where key = keyname;
  if found then
    result := true;
  end if;
  return result;
end;
$$ language 'plpgsql';

-- KVGET: Returns the string value of the key.
--        If the key does not exist, NULL is returned instead.
--  ARG1: keyname varchar
--  RTRN: text
--
-- EXAMPLE 1:
--  select * from kvget('abc');
--      kvget
--  -------------
--   hello world
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvget('nonexistent');
--   kvget
--  --------
--   <NULL>
--  (1 row)
create or replace function kvget(keyname varchar) returns text as $$
declare
  result text;
begin
  select value from keyval.strings where key = keyname into result;
  return result;
end;
$$ language 'plpgsql';

-- KVGETSET: Sets the key to hold a string value and returns the old value stored.
--           If no value was previously stored, NULL is returned instead.
--  ARG1: keyname varchar
--  ARG2: valuestring text
--  RTRN: text
--
-- EXAMPLE 1:
--  select * from kvgetset('abc', 'hello world');
--   kvgetset
--  ----------
--   <NULL>
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvgetset('abc', 'howdy partner');
--     kvgetset
--  -------------
--   hello world
--  (1 row)
create or replace function kvgetset(keyname varchar, valuestring text) returns text as $$
declare
  result text;
begin
  select value from keyval.strings where key = keyname into result;
  if found then
    update keyval.strings set value = valuestring, updated_at = now() where key = keyname;
  else
    insert into keyval.strings (key, value, created_at, updated_at) values (keyname, valuestring, now(), now());
  end if;
  return result;
end;
$$ language 'plpgsql';

-- KVLEN: Returns the length of the string value of the key.
--        If no value was previously stored, NULL is returned instead.
--  ARG1: keyname varchar
--  RTRN: int
--
-- EXAMPLE 1:
--  select * from kvlen('abc');
--   kvlen
--  -------
--      11
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvlen('nonexistent');
--   kvlen
--  --------
--   <NULL>
--  (1 row)
create or replace function kvlen(keyname varchar) returns int as $$
declare
  result int;
begin
  select char_length(value) from keyval.strings where key = keyname into result;
  if not found then
    result := null;
  end if;
  return result;
end;
$$ language 'plpgsql';

-- KVMGET: Returns the key and string values of all specified keys.
--         For any keys specified that do not have a string value, NULL is returned instead.
--  ARG1: keynames varchar[]
--  RTRN: table(key varchar, value text)
--
-- EXAMPLE 1:
--  select * from kvmget(array['abc', 'nonexistent', 'def', 'nonexistent']);
--       key     |     value
--  -------------+---------------
--   abc         | hello world
--   nonexistent | <NULL>
--   def         | howdy partner
--   nonexistent | <NULL>
--  (4 rows)
create or replace function kvmget(keynames varchar[]) returns table(key varchar, value text) as $$
begin
  return query with
    keys as (select unnest(keynames))
    select keys.unnest, strings.value from keys
    left outer join keyval.strings on strings.key = keys.unnest;
end;
$$ language 'plpgsql';

-- KVMSET: Sets all keys to their respective string values.
--         For any keys that already hold a value, it will be overwritten instead.
--         If more keys then values are given, the extra values will be set to NULL.
--         If more values then keys are given, the extra values will be ignored.
--  ARG1: keynames varchar[]
--  ARG2: valuestrings text[]
--  RTRN: void
--
-- EXAMPLE 1:
--  select * from kvmset(array['a', 'b', 'c'], array['apple', 'banana', 'cherry']);
--   kvmset
--  --------
--
--  (1 row)
create or replace function kvmset(keynames varchar[], valuestrings text[]) returns void as $$
declare
  keyname varchar;
  i int := 1;
begin
  foreach keyname in array keynames loop
    update keyval.strings set value = valuestrings[i], updated_at = now() where key = keyname;
    if not found then
      insert into keyval.strings (key, value, created_at, updated_at) values (keyname, valuestrings[i], now(), now());
    end if;
    i := i + 1;
  end loop;
end;
$$ language 'plpgsql';

-- KVMSETNX: Sets all keys to their respective string values, if all of the keys specified have not been set already.
--           If any of the specified keys have already been set to a string value, this function will do nothing.
--           For any keys that already hold a value, it will be overwritten instead.
--           If more keys then values are given, the extra values will be set to NULL.
--           If more values then keys are given, the extra values will be ignored.
--  ARG1: keynames varchar[]
--  ARG2: valuestrings text[]
--  RTRN: void
--
-- EXAMPLE 1:
--  select * from kvmsetnx(array['a', 'b', 'c'], array['apple', 'banana', 'cherry']);
--   kvmsetnx
--  ----------
--
--  (1 row)
create or replace function kvmsetnx(keynames varchar[], valuestrings text[]) returns void as $$
declare
  keyname varchar;
  i int := 1;
begin
  perform key from keyval.strings where key = any(keynames) limit 1;
  if not found then
    foreach keyname in array keynames loop
      update keyval.strings set value = valuestrings[i], updated_at = now() where key = keyname;
      if not found then
        insert into keyval.strings (key, value, created_at, updated_at) values (keyname, valuestrings[i], now(), now());
      end if;
      i := i + 1;
    end loop;
  end if;
end;
$$ language 'plpgsql';

-- KVSET: Sets the key to hold a string value.
--        If key already holds a value, it is overwritten instead.
--  ARG1: keyname varchar
--  ARG2: valuestring text
--  RTRN: void
--
-- EXAMPLE 1:
--  select * from kvset('abc', 'hello world');
--   kvset
--  -------
--
--  (1 row)
create or replace function kvset(keyname varchar, valuestring text) returns void as $$
begin
  update keyval.strings set value = valuestring, updated_at = now() where key = keyname;
  if not found then
    insert into keyval.strings (key, value, created_at, updated_at) values (keyname, valuestring, now(), now());
  end if;
end;
$$ language 'plpgsql';

-- KVSETNX: Sets the key to hold a string value, if the key does not exist, and returns TRUE.
--          If the key already has a value set, no change is made and FALSE is returned instead.
--  ARG1: keyname varchar
--  ARG2: valuestring text
--  RTRN: boolean
--
-- EXAMPLE 1:
--  select * from kvsetnx('abc', 'hello world');
--   kvsetnx
--  ---------
--   t
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvsetnx('abc', 'howdy partner');
--   kvsetnx
--  ---------
--   f
--  (1 row)
create or replace function kvsetnx(keyname varchar, valuestring text) returns boolean as $$
declare
  result boolean := true;
begin
  begin
    insert into keyval.strings (key, value, created_at, updated_at) values (keyname, valuestring, now(), now());
  exception when unique_violation then
    result := false;
  end;
  return result;
end;
$$ language 'plpgsql';

-- KVNDEL: Deletes the number value held by the key and returns TRUE.
--         If the key does not exist, FALSE is returned instead.
--  ARG1: keyname varchar
--  RTRN: boolean
--
-- EXAMPLE 1:
--  select * from kvndel('abc');
--   kvndel
--  --------
--   t
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvndel('nonexistent');
--
--   kvndel
--  --------
--   f
--  (1 row)
create or replace function kvndel(keyname varchar) returns boolean as $$
declare
  result boolean := false;
begin
  delete from keyval.numbers where key = keyname;
  if found then
    result := true;
  end if;
  return result;
end;
$$ language 'plpgsql';

-- KVNGET: Returns the number value of the key.
--         If the key does not exist, NULL is returned instead.
--  ARG1: keyname varchar
--  RTRN: text
--
-- EXAMPLE 1:
--  select * from kvnget('abc');
--   kvnget
--  --------
--        5
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvnget('nonexistent');
--   kvnget
--  --------
--   <NULL>
--  (1 row)
create or replace function kvnget(keyname varchar) returns int as $$
declare
  result int;
begin
  select value from keyval.numbers where key = keyname into result;
  return result;
end;
$$ language 'plpgsql';

-- KVINCRBY: Increments the value stored at the key by the number given.
--           If the key does not have a value, the number given becomes the new value instead.
--  ARG1: keyname varchar
--  ARG2: valuenumber int
--  RTRN: int
--
-- EXAMPLE 1:
--  select * from kvincrby('abc', 5);
--   kvincrby
--  ----------
--          5
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvincrby('abc', 3);
--   kvincrby
--  ----------
--          8
--  (1 row)
create or replace function kvincrby(keyname varchar, valuenumber int) returns int as $$
declare
  result int;
begin
  update keyval.numbers set value = (value + valuenumber), updated_at = now() where key = keyname returning value into result;
  if result is null then
    insert into keyval.numbers (key, value, created_at, updated_at) values (keyname, valuenumber, now(), now());
    result := valuenumber;
  end if;
  return result;
end;
$$ language 'plpgsql';

-- KVINCR: Increments the value stored at the key by 1.
--           If the key does not have a value, the new value becomes 1 instead.
--  ARG1: keyname varchar
--  RTRN: int
--
-- EXAMPLE 1:
--  select * from kvincr('abc');
--   kvincr
--  --------
--       9
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvincr('nonexistent');
--   kvincr
--  --------
--        1
--  (1 row)
create or replace function kvincr(keyname varchar) returns int as $$
begin
  return kvincrby(keyname, 1);
end;
$$ language 'plpgsql';

-- KVDECRBY: Decrements the value stored at the key by the number given.
--           If the key does not have a value, the number given becomes the new negative value instead.
--  ARG1: keyname varchar
--  ARG2: valuenumber int
--  RTRN: int
--
-- EXAMPLE 1:
--  select * from kvdecrby('abc', 2);
--   kvdecrby
--  ----------
--         7
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvdecrby('nonexistent', 3);
--   kvdecrby
--  ----------
--         -3
--  (1 row)
create or replace function kvdecrby(keyname varchar, valuenumber int) returns int as $$
begin
  return kvincrby(keyname, (valuenumber - (valuenumber * 2)));
end;
$$ language 'plpgsql';

-- KVINCR: Decrements the value stored at the key by 1.
--         If the key does not have a value, the new value becomes -1 instead.
--  ARG1: keyname varchar
--  RTRN: int
--
-- EXAMPLE 1:
--  select * from kvdecr('abc');
--   kvdecr
--  --------
--        6
--  (1 row)
--
-- EXAMPLE 2:
--  select * from kvdecr('nonexistent');
--   kvdecr
--  --------
--       -1
--  (1 row)
create or replace function kvdecr(keyname varchar) returns int as $$
begin
  return kvdecrby(keyname, 1);
end;
$$ language 'plpgsql';

-- hash set function
create or replace function kvhset(keyname varchar, valuename text, valuestring text) returns void as $$
begin
  update keyval.hashes set value = (value || hstore(valuename, valuestring)), updated_at = now() where key = keyname;
  if not found then
    insert into keyval.hashes (key, value, created_at, updated_at) values (keyname, hstore(valuename, valuestring), now(), now());
  end if;
end;
$$ language 'plpgsql';

-- hash get function
create or replace function kvhget(keyname varchar, valuename text) returns text as $$
declare
  result text;
begin
  select (value -> valuename) from keyval.hashes where key = keyname into result;
  return result;
end;
$$ language 'plpgsql';

-- hash keys function
create or replace function kvhkeys(keyname varchar) returns table(key text) as $$
begin
  return query select skeys(value) from keyval.hashes where keyval.hashes.key = keyname;
end;
$$ language 'plpgsql';

-- hash values function
create or replace function kvhvalues(keyname varchar) returns table(value text) as $$
begin
  return query select svalues(value) from keyval.hashes where keyval.hashes.key = keyname;
end;
$$ language 'plpgsql';

-- hash getall function
create or replace function kvhgetall(keyname varchar) returns table(key text, value text) as $$
begin
  return query select skeys(keyval.hashes.value), svals(keyval.hashes.value) from keyval.hashes where keyval.hashes.key = keyname;
end;
$$ language 'plpgsql';

-- hash exists function
create or replace function kvhexists(keyname varchar, valuename text) returns boolean as $$
declare
  result boolean;
begin
  select coalesce((exist(value, valuename)), false) from keyval.hashes where key = keyname into result;
  if not found then
    result := false;
  end if;
  return result;
end;
$$ language 'plpgsql';

-- hash del function
create or replace function kvhdel(keyname varchar, valuename text) returns boolean as $$
declare
  hashvalue hstore;
  result boolean := false;
begin
  select value from keyval.hashes where key = keyname into hashvalue;
  if found then
    if (hashvalue -> valuename) is not null then
      result := true;
      if array_length(hkeys(hashvalue), 1) > 1 then
        update keyval.hashes set value = (value - valuename), updated_at = now() where key = keyname;
      else
        delete from keyval.hashes where key = keyname;
      end if;
    end if;
  end if;
  return result;
end;
$$ language 'plpgsql';

-- hash setnx function
create or replace function kvhsetnx(keyname varchar, valuename text, valuestring text) returns boolean as $$
declare
  result boolean := true;
begin
  begin
    insert into keyval.hashes (key, value, created_at, updated_at) values (keyname, hstore(valuename, valuestring), now(), now());
  exception when unique_violation then
    update keyval.hashes set value = (value || hstore(valuename, valuestring)) where key = keyname and value ? valuename = false;
    if not found then
      result := false;
    end if;
  end;
  return result;
end;
$$ language 'plpgsql';

-- hash mget function
create or replace function kvhmget(keyname varchar, valuenames text[]) returns table(key text, value text) as $$
begin
  return query with
    pairs as (select skeys(keyval.hashes.value), svals(keyval.hashes.value) from keyval.hashes where keyval.hashes.key = keyname),
    keys as (select unnest(valuenames))
    select unnest, svals from keys left outer join pairs on pairs.skeys = keys.unnest;
end;
$$ language 'plpgsql';
-- Transactional production contract test. It leaves no data or test objects.
begin;

do $$
declare
  first_snapshot jsonb := jsonb_build_array(
    jsonb_build_object(
      'source_id', 'duplicate-source-id',
      'name', '__contract_active_a__',
      'full_name', '__contract_active_a__',
      'start_at', '2099-01-01T00:00:00+08:00',
      'end_at', '2099-01-02T00:00:00+08:00',
      'province', '测试省',
      'city', '测试市',
      'address', '测试省·测试市',
      'venue', null,
      'cover', null,
      'status', 'preview',
      'source_state', 1,
      'source_state_text', '预告',
      'source_url', 'https://www.furryfusion.net/contract-a',
      'source_path', '/contract-a',
      'detail', null,
      'organization', '测试组织',
      'updated_at', '2099-01-01T00:00:00Z'
    ),
    jsonb_build_object(
      'source_id', 'duplicate-source-id',
      'name', '__contract_active_b__',
      'full_name', '__contract_active_b__',
      'start_at', '2099-02-01T00:00:00+08:00',
      'end_at', '2099-02-02T00:00:00+08:00',
      'province', null,
      'city', '测试市',
      'address', '测试市',
      'venue', null,
      'cover', null,
      'status', 'confirmed',
      'source_state', 2,
      'source_state_text', '确认',
      'source_url', 'https://www.furryfusion.net/contract-b',
      'source_path', '/contract-b',
      'detail', null,
      'organization', '测试组织',
      'updated_at', '2099-01-01T00:00:00Z'
    )
  );
  second_snapshot jsonb;
  legacy_before jsonb;
  source_before_empty jsonb;
  empty_rejected boolean := false;
  duplicate_rejected boolean := false;
  fault_rejected boolean := false;
begin
  insert into public.furry_events(name, start_at, source, is_active, detail)
  values ('__contract_legacy__', '2099-03-01T00:00:00+08:00', 'legacy', true, 'untouched');

  select to_jsonb(row_value)
  into legacy_before
  from (
    select name, start_at, source, is_active, detail
    from public.furry_events
    where name = '__contract_legacy__'
  ) row_value;

  begin
    perform public.sync_furry_events(
      jsonb_build_array(first_snapshot -> 0, first_snapshot -> 0),
      '2098-12-31T00:00:00Z',
      false
    );
  exception when others then
    duplicate_rejected := sqlerrm = 'DUPLICATE_EVENT_KEY';
  end;
  if not duplicate_rejected then
    raise exception 'duplicate (name, start_at) was not rejected';
  end if;

  perform public.sync_furry_events(first_snapshot, '2099-01-01T00:00:00Z', false);

  if (select count(*) from public.furry_events
      where source_id = 'duplicate-source-id'
        and source = 'furfantasia_event_data') <> 2 then
    raise exception 'duplicate source_id contract failed';
  end if;

  second_snapshot := jsonb_build_array(first_snapshot -> 1);
  perform public.sync_furry_events(second_snapshot, '2099-01-02T00:00:00Z', false);

  if (select is_active from public.furry_events
      where name = '__contract_active_a__') is distinct from false then
    raise exception 'missing event was not deactivated';
  end if;

  perform public.sync_furry_events(first_snapshot, '2099-01-03T00:00:00Z', false);
  if (select is_active from public.furry_events
      where name = '__contract_active_a__') is distinct from true then
    raise exception 'reappearing event was not reactivated';
  end if;

  select jsonb_agg(to_jsonb(row_value) order by row_value.id)
  into source_before_empty
  from (
    select *
    from public.furry_events
    where source = 'furfantasia_event_data'
  ) row_value;

  begin
    perform public.sync_furry_events('[]'::jsonb, '2099-01-04T00:00:00Z', false);
  exception when others then
    empty_rejected := sqlerrm = 'EMPTY_SNAPSHOT_REJECTED';
  end;
  if not empty_rejected then
    raise exception 'empty snapshot was not rejected';
  end if;
  if (select count(*) from public.furry_events
      where source = 'furfantasia_event_data' and is_active) <> 2 then
    raise exception 'empty snapshot rejection changed active rows';
  end if;
  if source_before_empty is distinct from (
    select jsonb_agg(to_jsonb(row_value) order by row_value.id)
    from (
      select *
      from public.furry_events
      where source = 'furfantasia_event_data'
    ) row_value
  ) then
    raise exception 'empty snapshot rejection changed database fields';
  end if;

  if legacy_before is distinct from (
    select to_jsonb(row_value)
    from (
      select name, start_at, source, is_active, detail
      from public.furry_events
      where name = '__contract_legacy__'
    ) row_value
  ) then
    raise exception 'legacy record was modified';
  end if;

  execute $ddl$
    create function pg_temp.reject_furry_deactivation()
    returns trigger
    language plpgsql
    as $trigger$
    begin
      if old.source = 'furfantasia_event_data'
         and old.is_active = true
         and new.is_active = false then
        raise exception 'INJECTED_SYNC_FAILURE';
      end if;
      return new;
    end;
    $trigger$
  $ddl$;

  execute $ddl$
    create trigger furry_event_contract_failure
    before update on public.furry_events
    for each row execute function pg_temp.reject_furry_deactivation()
  $ddl$;

  begin
    perform public.sync_furry_events(
      jsonb_build_array(first_snapshot -> 0),
      '2099-01-05T00:00:00Z',
      false
    );
  exception when others then
    fault_rejected := sqlerrm = 'INJECTED_SYNC_FAILURE';
  end;
  if not fault_rejected then
    raise exception 'fault injection did not abort the sync';
  end if;
  if (select last_seen_at from public.furry_events
      where name = '__contract_active_a__') <> '2099-01-03T00:00:00Z'::timestamptz then
    raise exception 'failed sync did not roll back its upsert';
  end if;

  execute 'drop trigger furry_event_contract_failure on public.furry_events';

  perform public.sync_furry_events('[]'::jsonb, '2099-01-06T00:00:00Z', true);
  if (select count(*) from public.furry_events
      where source = 'furfantasia_event_data' and is_active) <> 0 then
    raise exception 'allow_empty did not deactivate the new source';
  end if;

  raise notice 'FURRY_EVENT_SYNC_CONTRACT_PASS';
end;
$$;

rollback;

select 'FURRY_EVENT_SYNC_CONTRACT_PASS' as result;

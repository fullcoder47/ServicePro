import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';

// User IDs are NEVER accepted from the request body. The JWT identifies the
// sole account that may be deleted. The service role stays on the server.
serve(async (request) => {
  if (request.method !== 'POST') {
    return Response.json({ error: 'method_not_allowed' }, { status: 405 });
  }

  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return Response.json({ error: 'unauthorized' }, { status: 401 });

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return Response.json({ error: 'server_not_configured' }, { status: 503 });
  }

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(token);
  if (authError || !authData.user) {
    return Response.json({ error: 'unauthorized' }, { status: 401 });
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const userId = authData.user.id;
  const { data: profile, error: profileError } = await admin.from('profiles')
    .select('role').eq('id', userId).maybeSingle();
  if (profileError) return Response.json({ error: 'profile_check_failed' }, { status: 503 });
  if (!profile) return Response.json({ error: 'profile_missing' }, { status: 404 });

  // Directors own a company FK; deleting one can cascade through the entire
  // company. Staff accounts can own historical tickets/invitations as well.
  // Those roles require an administrator to transfer responsibilities first.
  if (profile.role !== 'user') {
    return Response.json({ error: 'organization_account_protected' }, { status: 409 });
  }
  const { data: companies, error: companyError } = await admin.from('companies')
    .select('id').eq('director_id', userId).limit(1);
  if (companyError || (companies?.length ?? 0) > 0) {
    return Response.json({ error: 'organization_account_protected' }, { status: 409 });
  }

  // Supabase Auth refuses to remove users who own Storage objects. List only
  // objects belonging to this JWT identity and delete via the Storage API.
  const { data: ownedFiles, error: filesError } = await userClient.rpc(
    'servicepro_my_owned_storage_objects',
  );
  if (filesError || !Array.isArray(ownedFiles)) {
    return Response.json({ error: 'profile_delete_setup_missing' }, { status: 503 });
  }

  const byBucket = new Map<string, Set<string>>();
  for (const item of ownedFiles) {
    const bucket = item.bucket_id;
    const path = item.object_name;
    if (typeof bucket !== 'string' || typeof path !== 'string') {
      return Response.json({ error: 'invalid_storage_metadata' }, { status: 500 });
    }
    if (!byBucket.has(bucket)) byBucket.set(bucket, new Set());
    byBucket.get(bucket)!.add(path);
  }
  for (const [bucket, names] of byBucket) {
    const paths = [...names];
    for (let start = 0; start < paths.length; start += 100) {
      const { error } = await admin.storage.from(bucket).remove(paths.slice(start, start + 100));
      if (error) return Response.json({ error: 'storage_cleanup_failed' }, { status: 503 });
    }
  }

  // Hard delete, NOT soft delete. ON DELETE CASCADE removes the profile and
  // its own ticket/chat rows. Never delete an arbitrary supplied account ID.
  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    return Response.json({ error: 'account_delete_failed' }, { status: 503 });
  }
  return Response.json({ deleted: true });
});

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://kfsccpuyvebzwfkhldrf.supabase.co',
);

const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_KEY',
  defaultValue: 'sb_publishable_oW6oVwK9EZ_ESd2BAMc6HA_yF8ya4kw',
);

const appRedirectUrl = String.fromEnvironment(
  'APP_URL',
  defaultValue: 'http://localhost:3000',
);

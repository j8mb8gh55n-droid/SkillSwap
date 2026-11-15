SELECT to_regclass('public.profiles') IS NOT NULL AS profiles_present,
       to_regprocedure('auth.uid()') IS NOT NULL AS auth_uid_present,
       to_regrole('authenticated') IS NOT NULL AND to_regrole('anon') IS NOT NULL AS roles_present,
       to_regclass('public.chat_conversations') IS NULL
           AND to_regclass('public.chat_messages') IS NULL
           AND to_regclass('public.chat_messages_id_seq') IS NULL
           AND to_regclass('public.chat_conversations_pair_idx') IS NULL
           AND NOT EXISTS (
               SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
               WHERE n.nspname = 'public' AND p.proname IN (
                   'chat_introduce', 'chat_respond', 'chat_send', 'chat_block',
                   'chat_mark_read', 'chat_unread_counts'
               )
           ) AS messaging_names_available;

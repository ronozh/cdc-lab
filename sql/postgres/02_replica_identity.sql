ALTER TABLE public.transaction REPLICA IDENTITY FULL;   -- write the whole old row to WAL on update/delete

-- signup form needs users to pick their uni, but don't expose any more than necessary
grant select (id, name) on universities to public;


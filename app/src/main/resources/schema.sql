CREATE TABLE IF NOT EXISTS book (
    id     bigint PRIMARY KEY,
    title  text NOT NULL,
    author text NOT NULL
);

INSERT INTO book (id, title, author) VALUES
    (1, 'Der Zauberberg', 'Thomas Mann'),
    (2, 'Buddenbrooks', 'Thomas Mann'),
    (3, 'Der Process', 'Franz Kafka'),
    (4, 'Das Schloss', 'Franz Kafka'),
    (5, 'Effi Briest', 'Theodor Fontane')
ON CONFLICT (id) DO NOTHING;

-- Business table for the "oldest / newest row" metrics (config/alloy/business-queries.yaml)
CREATE TABLE IF NOT EXISTS catch (
    id        bigserial PRIMARY KEY,
    species   text        NOT NULL,
    caught_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO catch (species, caught_at)
SELECT 'pike', now() - interval '30 days'
WHERE NOT EXISTS (SELECT FROM catch);

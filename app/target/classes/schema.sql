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

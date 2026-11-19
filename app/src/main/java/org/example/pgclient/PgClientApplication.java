package org.example.pgclient;

import java.util.List;
import java.util.Map;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@RestController
public class PgClientApplication {

    private final JdbcTemplate jdbc;

    public PgClientApplication(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public static void main(String[] args) {
        SpringApplication.run(PgClientApplication.class, args);
    }

    @GetMapping("/books")
    public List<Map<String, Object>> books() {
        return jdbc.queryForList("SELECT id, title, author FROM book ORDER BY id");
    }

    @GetMapping("/books/{id}")
    public Map<String, Object> book(@PathVariable long id) {
        return jdbc.queryForMap("SELECT id, title, author FROM book WHERE id = ?", id);
    }

    /** Each call adds a row: moves fish_catch_newest_timestamp_seconds. */
    @PostMapping("/catches")
    public Map<String, Object> addCatch(@RequestParam(defaultValue = "trout") String species) {
        return jdbc.queryForMap("INSERT INTO catch (species) VALUES (?) RETURNING id, species, caught_at", species);
    }

    /** Slower than log_min_duration_statement (1 s): shows up in the slow query log, too. */
    @GetMapping("/report")
    public Map<String, Object> report() {
        return jdbc.queryForMap(
                "SELECT count(*) AS books, pg_sleep(1.2)::text AS slept FROM book b JOIN book c ON b.author = c.author");
    }
}

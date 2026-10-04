# Generative AI Use

This project used generative AI tools from Anthropic: Claude (claude.ai) and Claude Code. As the course policy requires, this file lists which parts of the project AI produced, how we checked its output, and why it did not replace our own learning of the course competencies.

## Summary

| Part of the project                               | AI's role                                                                 | Our role                                                                                                              |
| ------------------------------------------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Seed data (`seed.sql`)                            | Generated the sample rows                                                 | Defined the schema the data had to fit; reviewed and verified the data                                                |
| `README.md`                                       | Drafted the run instructions and file map                                 | Reviewed the steps and wrote the AI citation section ourselves                                                        |
| `sprints/goal-d-draft.md`                         | Drafted the next-sprint plan for goal D, including an SQL sketch          | Chose the goal, reviewed the reasoning, will fill in the competency, and will do the actual 4NF work next sprint      |
| `docs/lossless-join.md`, `sql/lossless_check.sql` | Helped draft the goal B write-up and the join-back SQL                    | Chose the three decompositions and the FDs, checked every chase step by hand, ran the SQL, picked the competency      |
| `docs/dependency-preservation.md`                 | Helped draft the goal C per-FD list and the BCNF vs 3NF watchlist example | Picked the FDs and the one-list rule, ran the SQL sketch, picked the competency, will decide BCNF vs 3NF              |
| `docs/normalization.md`                           | Drafted the per-table FD list and BCNF check for the 4 implemented tables | Chose the FDs from our requirements, verified every determinant is a superkey, will redo after goal A's minimal cover |

Our design work was done by the team without AI: the requirements, the ERD, the relational schema (`ddl.sql`).

## Details

### Seed data

- **What AI did:** Claude Code generated realistic, fictional sample data for our schema in `ddl.sql`: users, stocks, transactions and holdings. It was committed in 960f953.
- **How we checked it:** We loaded the data into an empty MySQL 8.0 database by following the README, and confirmed the row counts: 9 users, 14 stocks, 82 transactions and 22 holds. We also checked that the data is consistent with our own business rules.
- **Why this does not undermine our learning:** Sample data is not a course competency. Writing hundreds of `INSERT` statements by hand is not part of designing or normalizing a schema. The data is only there so that we can demonstrate the schema we designed. Every table and constraint the data must satisfy came from our own design.

### README

- **What AI did:** Claude Code drafted the run instructions (Docker or local MySQL 8.0), the expected row-count check and the file map. It also renamed `readme.md` to `README.md` so that our CI finds it.
- **How we checked it:** Claude Code ran a fresh-clone test against an empty MySQL 8.0 server, using exactly the commands in the README. A team member then reran the steps to confirm them.
- **Why this does not undermine our learning:** The README documents how to run the project. It contains no database design. This AI citation section was written by the team.

### Goal D plan (`sprints/goal-d-draft.md`)

- **What AI did:** Claude Code drafted the plan for goal D (multivalued dependencies and 4NF) for the next sprint. The draft follows our plan structure (limitation, goal, competency, objective measure, artifact). It includes an SQL sketch showing that adding one tag takes 3 rows before the 4NF decomposition and 1 row after, and that joining the tables back recovers the original rows. The SQL was tested on MySQL 8.0.
- **How we checked it:** The team member who owns goal D reviewed the draft and can explain the MVD `ticker ↠ tag | theme`, why the combined table is in BCNF but not in 4NF, and why the decomposition is lossless.
- **Why this does not undermine our learning:** The draft is a plan, not completed work. The 4NF analysis itself, the new tables in the DDL and the demo SQL will be done by the team next sprint, and will be presented as evidence then. The competency mapping uses the exact wording from Brightspace, which the team fills in.

### Goal B draft (`docs/lossless-join.md`, `sql/lossless_check.sql`)

- **What AI did:** Claude Code helped draft the goal B write-up (chase tests on stock/exchange, orders/trade and watchlist/watchlist_item, plus one deliberately lossy split) and the SQL script that joins each decomposition back and compares it with the original relation.
- **How we checked it:** The goal B owner redid each chase tableau by hand, checked it against the binary shortcut (R1 ∩ R2 → R1 or R2), and ran `sql/lossless_check.sql` on MySQL 8: the three real decompositions pass and the bad split gives 3 spurious rows.
- **Why this does not undermine our learning:** The goal B owner can explain why each chase ends with a row of all distinguished variables, why the ticker split is lossy, and why open orders missing from the join are not lost data. The competency mapping was picked by the team from the Brightspace wording.

### Goal C draft (`docs/dependency-preservation.md`)

- **What AI did:** Claude Code helped draft the per-FD list (which table and key enforces each FD) and the watchlist example where BCNF and 3NF differ, including an SQL sketch.
- **How we checked it:** We checked each FD against our requirements, confirmed that user_id, ticker → watchlist_id is lost in the BCNF split, and ran the SQL sketch on MySQL 8: the BCNF tables accept the duplicate and the 3NF table rejects it with error 1062.
- **Why this does not undermine our learning:** The draft is a starting point. The goal C owner makes the BCNF vs 3NF decision and redoes the list once goal A's minimal cover is done.

### Normalization doc (`docs/normalization.md`)

- **What AI did:** Muse drafted the per-table FD list, candidate keys and BCNF check for the 4 tables in `sql/ddl.sql` (user, stock, transaction, holds), plus the "chose not to store" case (total position value in holds) and the known-limitations section.
- **How we checked it:** The goal 2 owner verified each FD and key against `sql/ddl.sql`, checked that every determinant is a superkey, and confirmed the doc matches the implemented schema. The doc will be redone if goal A's minimal cover comes out different.
- **Why this does not undermine our learning:** The FDs and the schema design are the team's own; the draft only organized them into the per-table BCNF check. The goal 2 owner can explain every table, FD and design decision, and presents this as evidence in the video.

## Our commitment

Every team member can explain any table, functional dependency and design decision in this repository without AI assistance. If generative AI is used in later sprints, we will add it to this file.

# Generative AI Use

This project used generative AI tools from Anthropic: Claude (claude.ai) and Claude Code. As the course policy requires, this file lists which parts of the project AI produced, how we checked its output, and why it did not replace our own learning of the course competencies.

## Summary

| Part of the project | AI's role | Our role |
|---|---|---|
| Seed data (`seed.sql`) | Generated the sample rows | Defined the schema the data had to fit; reviewed and verified the data |
| `README.md` | Drafted the run instructions and file map | Reviewed the steps and wrote the AI citation section ourselves |
| `sprints/goal-d-draft.md` | Drafted the next-sprint plan for goal D, including an SQL sketch | Chose the goal, reviewed the reasoning, will fill in the competency, and will do the actual 4NF work next sprint |

Our design work was done by the team without AI: the requirements, the ERD, the relational schema (`ddl.sql`), and the normalization analysis.

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

## Our commitment

Every team member can explain any table, functional dependency and design decision in this repository without AI assistance. If generative AI is used in later sprints, we will add it to this file.
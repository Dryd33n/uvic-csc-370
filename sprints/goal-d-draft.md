# Next-sprint goal D: MVDs and 4NF (draft)

Goal D adds two independent multivalued facts about a stock (tags and themes) and shows that adding one tag takes 3 rows before the 4NF decomposition and 1 row after.

| | |
| --- | --- |
| **Limitation** | The schema has no multivalued data, so we cannot yet show that we can apply a normal form beyond BCNF (Data Modelling, Level 3). |
| **Goal** | Add stock tags (`large-cap`, `dividend`, ...) and investment themes (`AI`, `services`, ...). They vary independently, so storing both in one table creates the MVD `ticker ↠ tag \| theme`. Decompose it into 4NF. |
| **Competency** | Data Modelling, Level 3: "Applies alternative normal forms when they better suit the application requirements." Also Level 2: "Eliminates data anomalies with effective normalisation." |
| **Objective measure** | Adding one tag to a stock with 3 themes inserts 3 rows before the decomposition and 1 row after. Joining the two new tables back gives exactly the original rows. |
| **Artifact** | `docs/4nf.md`, the new tables in the DDL, and `sql/4nf_demo.sql` |

## Depends on

- A primary key on `stock.ticker`, so the new tag and theme tables can reference it with foreign keys. The current `sql/ddl.sql` has no keys.

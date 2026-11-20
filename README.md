# Getting Started with Cortex Sense

Companion repository for the
[Getting Started with Cortex Sense](https://www.snowflake.com/en/developers/guides/getting-started-with-cortex-sense/)
quickstart.

It sets up **Juniper Valley Health**, a fictional health system, in your Snowflake account.
Its analytics warehouse holds about 16,000 synthetic rows. Its business definitions, such as
what counts as a clean claim, which admissions a readmission rate excludes, and what its
internal BEACON designation requires, are in internal docs, saved queries, and a
dashboard, as they would be at a real organization. You ask an agent the same questions without
and with a Cortex Sense context over those sources, and compare the answers.

Everything in this repository is synthetic. No real patient data is used.

> Cortex Sense is in public preview. The setup scripts run in any account, but building
> the context requires Cortex Sense to be enabled on it. Contact your account team if
> `/sense` isn't available or the build reports that it isn't enabled.

## Quick start

1. Run [`admin_setup.sql`](admin_setup.sql) in a Snowsight SQL worksheet as
   `ACCOUNTADMIN`. It creates the two demo roles, the warehouse, the Git integration, and
   an empty database, and grants the Cortex Sense builder role. If you aren't an
   administrator, send it to one: they set `quickstart_user` to your user name and run it
   for you.
2. Run [`setup.sql`](setup.sql) as yourself. It runs entirely as `JUNIPER_BUILDER` and
   loads everything directly from this repository through Snowflake's Git integration, so
   there's nothing to clone or install.
3. Check that every row in the final result says `PASS`.
4. Follow the quickstart to build the Cortex Sense context and compare answers.

When you're done, delete the context through Cortex Code, then run
[`teardown.sql`](teardown.sql). Its second part needs `ACCOUNTADMIN`.

## What the setup scripts create

| Object | Purpose |
|---|---|
| `JUNIPER_BUILDER` role | Owns the demo and builds the Cortex Sense context |
| `JUNIPER_ANALYST` role | Reads the `ANALYTICS` schema only. Used for the comparison |
| `JUNIPER_WH` warehouse | XSMALL, auto-suspends after 60 seconds |
| `JUNIPER_GITHUB` API integration | Read-only access to this public repository |
| `JUNIPER_HEALTH.ANALYTICS` | 8 tables and the `CLAIMS_SV` semantic view. Structure only, no current business definitions |
| `JUNIPER_HEALTH.KNOWLEDGE` | Internal docs and saved queries on `KNOWLEDGE_STAGE`, the operations dashboard, and the `CLAIMS_SV_CERTIFIED` semantic view |
| `JUNIPER_HEALTH.SENSE` | Empty. The Cortex Sense context goes here |

Setup loads everything through a temporary `SETUP` schema holding the Git repository
clone, then drops it, because the clone includes the answer key.

`JUNIPER_ANALYST` can't read `KNOWLEDGE`. That separation is what makes the comparison
fair: without Cortex Sense, the analyst has the tables but not the definitions.

## Repository layout

```
admin_setup.sql               account-level setup, run once as ACCOUNTADMIN
setup.sql                     loads the demo, runs as JUNIPER_BUILDER
teardown.sql                  removes everything both scripts created
answer_key.sql                correct answers, computed from the base tables
data/                         8 CSVs loaded into ANALYTICS
knowledge/docs/               internal docs uploaded to KNOWLEDGE_STAGE/markdown/
knowledge/query-history/      saved queries uploaded to KNOWLEDGE_STAGE/query-history/
streamlit/streamlit_app.py    the operations dashboard
evals/questions.yaml          the 18 questions and their expected answers
evals/golden_values.json      expected answers written by the generator
scripts/generate_data.py      deterministic data generator
```

## The questions

[`evals/questions.yaml`](evals/questions.yaml) has 18 questions. Four are routine: the
schema alone answers them, so they check that the agent can query the data at all. The
other 14 need a definition, program rule, or policy from one of the four docs:

| Doc | Questions |
|---|---|
| None, the schema is enough | Denial rate, ACO facilities, share of charges paid, top payer by claims |
| `Metrics_Glossary.md` | Clean claim rate by payer, 30-day readmission rate, Experience Score by facility, facilities above the CMS threshold, highest readmission rate |
| `BEACON_Facility_Designation.md` | BEACON facilities, closest to BEACON, why a clinic isn't on the scorecard |
| `Project_Tailwind.md` | Tailwind rate, Tailwind rate by facility |
| `External_Data_Release_Policy.md` | Sending readmission rates to a partner, the small-cell threshold, whether a BAA covers a release, how to get approval |

Expected answers are in [`evals/questions.yaml`](evals/questions.yaml).

`answer_key.sql` reproduces them. Run it only after you've compared answers: anything you
run lands in query history, which Cortex Sense can read on the next build.

## Regenerating the data

```bash
python3 scripts/generate_data.py
```

The generator uses only the Python standard library and a fixed seed, so the output is
identical on every run. It ends with a set of gates that fail if any question stops
separating a guessed answer from the defined one. For example, the naive readmission rate
must stay above the CMS 18% threshold while the correct rate stays well below it.

If you change the data, update the expected row counts at the end of `setup.sql` and the
answers in `evals/questions.yaml`. The last gate fails if any number in
`evals/questions.yaml` no longer matches the data.

## License

Apache 2.0. See [LICENSE](LICENSE).

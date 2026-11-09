"""Generate the Juniper Valley Health dataset for the Cortex Sense quickstart.

Everything here is synthetic. The script is deterministic (fixed seed, standard
library only), writes eight CSVs to ../data, and writes the correct answers to
../evals/golden_values.json.

The data is shaped so that each definition-dependent question has a large gap
between the reading an agent would guess from the schema and the reading the
knowledge docs define. The gates at the bottom fail the run if any of those gaps
close, so a regeneration can never silently make the demo pointless.

Usage:
    python3 scripts/generate_data.py
"""

import csv
import json
import random
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

SEED = 20261106
ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "data"
GOLDEN_FILE = ROOT / "evals" / "golden_values.json"

START = datetime(2024, 1, 1)
END = datetime(2025, 12, 31)
# Inpatient stays end early enough that every readmission still falls inside the window.
INPATIENT_END = END - timedelta(days=60)

# ---------------------------------------------------------------------------
# Facilities. Inpatient volumes are fixed per facility so the readmission,
# BEACON and release-policy answers are controlled exactly.
#   elig        adult, non-obstetric, completed inpatient admissions
#   peds / ob   completed inpatient admissions that the house rate excludes
#   cancelled / in_progress   inpatient encounters with no discharge
#   readmits    unplanned readmissions within 30 days on eligible index admissions
#   late        unplanned readmissions after 30 days on eligible index admissions
#   planned     planned readmissions on eligible index admissions
#   trap_ob / trap_peds   unplanned readmissions on excluded index admissions
# ---------------------------------------------------------------------------
FACILITIES = [
    # id, name, type, city, aco
    (1, "Juniper Valley Medical Center", "Hospital", "Juniper Valley", True),
    (2, "Cedar Ridge Hospital", "Hospital", "Cedar Ridge", True),
    (3, "Riverbend Community Hospital", "Hospital", "Riverbend", False),
    (4, "Granite Falls Hospital", "Hospital", "Granite Falls", False),
    (5, "Willow Creek Hospital", "Hospital", "Willow Creek", True),
    (6, "Sagebrush Regional Hospital", "Hospital", "Sagebrush", False),
    (7, "Juniper Valley Women's and Children's Hospital", "Specialty Hospital", "Juniper Valley", False),
    (8, "Summit Orthopedic Hospital", "Specialty Hospital", "Cedar Ridge", True),
    (9, "Northgate Family Clinic", "Clinic", "Juniper Valley", True),
    (10, "Lakeside Clinic", "Clinic", "Riverbend", False),
    (11, "Mesa Primary Care", "Clinic", "Granite Falls", False),
    (12, "Pinehurst Clinic", "Clinic", "Willow Creek", False),
]

INPATIENT = {
    1: dict(elig=150, peds=6, ob=50, cancelled=6, in_progress=4, readmits=18, late=4, planned=6, trap_ob=22, trap_peds=2),
    2: dict(elig=130, peds=4, ob=30, cancelled=5, in_progress=3, readmits=12, late=3, planned=5, trap_ob=15, trap_peds=0),
    3: dict(elig=110, peds=8, ob=30, cancelled=4, in_progress=3, readmits=17, late=3, planned=4, trap_ob=13, trap_peds=2),
    4: dict(elig=18, peds=2, ob=8, cancelled=2, in_progress=1, readmits=3, late=0, planned=1, trap_ob=3, trap_peds=0),
    5: dict(elig=95, peds=3, ob=22, cancelled=3, in_progress=2, readmits=6, late=2, planned=3, trap_ob=10, trap_peds=0),
    6: dict(elig=15, peds=2, ob=6, cancelled=1, in_progress=1, readmits=2, late=1, planned=1, trap_ob=2, trap_peds=0),
    7: dict(elig=12, peds=80, ob=100, cancelled=3, in_progress=2, readmits=1, late=0, planned=1, trap_ob=36, trap_peds=24),
    8: dict(elig=60, peds=0, ob=0, cancelled=2, in_progress=1, readmits=3, late=1, planned=3, trap_ob=0, trap_peds=0),
}

# Outpatient and emergency volume per facility.
AMBULATORY = {
    1: (130, 90), 2: (120, 80), 3: (120, 80), 4: (60, 50), 5: (110, 70), 6: (60, 50),
    7: (90, 40), 8: (80, 10), 9: (260, 0), 10: (240, 0), 11: (230, 0), 12: (220, 0),
}

# Mean overall_rating (1-10) of patient surveys per facility.
SURVEY_MEAN = {1: 8.1, 2: 8.9, 3: 7.8, 4: 8.0, 5: 9.0, 6: 7.5, 7: 8.7, 8: 9.3,
               9: 8.4, 10: 8.2, 11: 8.0, 12: 8.3}

# Share of not-clean first-submission claims that carry a denial row, and the
# chance a resubmitted claim carries one. Facilities 2 and 8 rarely see denials.
DENIAL_SHARE = {1: 0.6, 2: 0.0, 3: 0.6, 4: 0.6, 5: 0.85, 6: 0.6, 7: 0.1, 8: 0.0,
                9: 0.5, 10: 0.5, 11: 0.5, 12: 0.5}
RESUBMIT_DENIAL = {2: 0.05, 8: 0.05}
RESUBMIT_DENIAL_DEFAULT = 0.25

# Payer behavior: (share of claims accepted on first submission,
#                  share of first-submission claims that are actually clean).
# UnitedHealthcare looks best on first-pass acceptance but is near worst once
# denials and unpaid claims are taken into account.
PAYERS = {
    "UnitedHealthcare": (0.94, 0.59),
    "Aetna": (0.87, 0.80),
    "Blue Cross Blue Shield": (0.82, 0.83),
    "Cigna": (0.86, 0.81),
    "Humana": (0.89, 0.72),
    "Medicare": (0.90, 0.73),
    "Medicaid": (0.84, 0.66),
    "Self-Pay": (0.85, 0.84),
}

PAYER_MIX = {
    "adult": [("UnitedHealthcare", 25), ("Aetna", 20), ("Blue Cross Blue Shield", 22),
              ("Cigna", 13), ("Humana", 5), ("Medicaid", 9), ("Self-Pay", 6)],
    "senior": [("Medicare", 80), ("Humana", 10), ("UnitedHealthcare", 10)],
    "child": [("Medicaid", 45), ("Blue Cross Blue Shield", 20), ("Aetna", 15),
              ("UnitedHealthcare", 15), ("Cigna", 5)],
    "ob": [("Medicaid", 35), ("Aetna", 15), ("Blue Cross Blue Shield", 20),
           ("UnitedHealthcare", 20), ("Cigna", 10)],
}

ACO_FAST_SHARE = 0.77
NON_ACO_FAST_SHARE = 0.25

DX = {
    "adult_ip": ["I50.9", "J18.9", "I21.4", "N39.0", "K35.80", "E11.65", "J44.1", "A41.9", "I63.9", "K80.20"],
    "ortho_ip": ["M17.11", "M16.11", "S72.001A", "M48.06", "M17.12"],
    "child_ip": ["J45.901", "J21.9", "K35.80", "S72.001A", "A08.4", "J18.9"],
    "ob_ip": ["O80", "O82", "O34.21", "O13.9", "O24.410", "O42.00"],
    "outpatient": ["Z00.00", "I10", "E11.9", "M54.50", "J06.9", "Z23", "E78.5"],
    "emergency": ["R07.9", "S93.401A", "R10.9", "S01.81XA", "J06.9", "R51.9"],
    "secondary": ["I10", "E78.5", "Z79.4", "E66.9", "F17.210", "Z87.891"],
    "ob_secondary": ["Z37.0", "Z3A.39", "Z37.0"],
}

CARC = [("CO-16", "Missing or invalid information"), ("CO-50", "Not medically necessary"),
        ("CO-97", "Bundled service"), ("CO-29", "Timely filing limit exceeded"),
        ("PR-1", "Deductible amount"), ("CO-4", "Modifier inconsistent with procedure"),
        ("CO-18", "Duplicate claim")]


def rand_ts(rng, start, end):
    span = int((end - start).total_seconds())
    return start + timedelta(seconds=rng.randrange(span))


def fmt(ts):
    return ts.strftime("%Y-%m-%d %H:%M:%S") if ts else ""


def weighted(rng, pairs):
    return rng.choices([p for p, _ in pairs], weights=[w for _, w in pairs])[0]


def main():
    rng = random.Random(SEED)

    patients = {}          # patient_id -> dict
    pools = defaultdict(list)
    next_patient = [1]

    def new_patient(kind):
        pid = next_patient[0]
        next_patient[0] += 1
        if kind == "child":
            age = rng.randint(1, 15)
            sex = rng.choice(["F", "M"])
        elif kind == "ob":
            age = rng.randint(20, 42)
            sex = "F"
        elif kind == "senior":
            age = rng.randint(66, 90)
            sex = rng.choice(["F", "M"])
        else:
            age = rng.randint(25, 64)
            sex = rng.choice(["F", "M"])
        dob = date(2024 - age, rng.randint(1, 12), rng.randint(1, 28))
        payer_kind = "senior" if age >= 65 else kind
        patients[pid] = dict(patient_id=pid, dob=dob.isoformat(), sex=sex,
                             zip_code=f"9{rng.randint(7000, 7999)}",
                             primary_payer=weighted(rng, PAYER_MIX[payer_kind]))
        pools[kind].append(pid)
        return pid

    def pick_patient(kind):
        if pools[kind] and rng.random() < 0.45:
            return rng.choice(pools[kind])
        return new_patient(kind)

    def adult_kind():
        return "senior" if rng.random() < 0.38 else "adult"

    encounters = []
    next_enc = [1]
    by_category = defaultdict(list)   # (facility_id, category) -> [encounter]

    def add_encounter(fid, category, etype, status, patient_kind):
        # Inpatient stays always get a new patient, so the only repeat inpatient
        # stays in the data are the ones recorded in READMISSIONS.
        pid = new_patient(patient_kind) if etype == "Inpatient" else pick_patient(patient_kind)
        if status == "In Progress":
            admit = rand_ts(rng, END - timedelta(days=6), END)
        elif etype == "Inpatient":
            admit = rand_ts(rng, START, INPATIENT_END)
        else:
            admit = rand_ts(rng, START, END)
        if status == "In Progress":
            discharge = None
        elif status == "Cancelled":
            # Cancelled after registration: the source system still stamps a discharge time.
            discharge = admit + timedelta(hours=rng.randint(1, 6))
        elif etype == "Inpatient":
            discharge = admit + timedelta(days=rng.randint(1, 7), hours=rng.randint(1, 10))
        elif etype == "Emergency":
            discharge = admit + timedelta(hours=rng.randint(2, 14))
        else:
            discharge = admit + timedelta(hours=rng.randint(1, 3))
        enc = dict(encounter_id=next_enc[0], patient_id=pid, facility_id=fid, encounter_type=etype,
                   admit_date=admit, discharge_date=discharge, status=status, category=category)
        next_enc[0] += 1
        encounters.append(enc)
        by_category[(fid, category)].append(enc)
        return enc

    for fid, spec in INPATIENT.items():
        for _ in range(spec["elig"]):
            add_encounter(fid, "elig", "Inpatient", "Completed", adult_kind())
        for _ in range(spec["peds"]):
            add_encounter(fid, "peds", "Inpatient", "Completed", "child")
        for _ in range(spec["ob"]):
            add_encounter(fid, "ob", "Inpatient", "Completed", "ob")
        for _ in range(spec["cancelled"]):
            add_encounter(fid, "cancelled", "Inpatient", "Cancelled", adult_kind())
        for _ in range(spec["in_progress"]):
            add_encounter(fid, "in_progress", "Inpatient", "In Progress", adult_kind())

    for fid, (n_out, n_ed) in AMBULATORY.items():
        for _ in range(n_out):
            kind = rng.choices(["adult", "senior", "child"], weights=[50, 35, 15])[0]
            add_encounter(fid, "outpatient", "Outpatient", "Completed", kind)
        for _ in range(n_ed):
            kind = rng.choices(["adult", "senior", "child"], weights=[50, 30, 20])[0]
            add_encounter(fid, "emergency", "Emergency", "Completed", kind)

    # ---------------- Readmissions ----------------
    # An index and its readmission come from the same facility and category pool,
    # and the readmission encounter is reassigned to the index patient. Pools are
    # sized so index and readmission encounters never overlap.
    readmissions = []

    def pair_events(fid, category, n, planned, days_range=(2, 29)):
        pool = [e for e in by_category[(fid, category)] if not e.get("used")]
        if len(pool) < 2 * n:
            raise SystemExit(f"facility {fid} {category}: pool {len(pool)} too small for {n} events")
        rng.shuffle(pool)
        for i in range(n):
            index, readmit = pool[2 * i], pool[2 * i + 1]
            index["used"] = readmit["used"] = True
            days = rng.randint(*days_range)
            readmit["patient_id"] = index["patient_id"]
            readmit["admit_date"] = index["discharge_date"] + timedelta(days=days, hours=rng.randint(0, 12))
            readmit["discharge_date"] = readmit["admit_date"] + timedelta(days=rng.randint(1, 6))
            readmissions.append(dict(index_encounter_id=index["encounter_id"],
                                     readmit_encounter_id=readmit["encounter_id"],
                                     days_to_readmit=days, is_planned=planned))

    for fid, spec in INPATIENT.items():
        pair_events(fid, "elig", spec["readmits"], False)
        pair_events(fid, "elig", spec["planned"], True)
        pair_events(fid, "elig", spec["late"], False, days_range=(31, 45))
        pair_events(fid, "ob", spec["trap_ob"], False)
        pair_events(fid, "peds", spec["trap_peds"], False)

    rng.shuffle(readmissions)
    for i, r in enumerate(readmissions, start=1):
        r["readmission_id"] = i

    # ---------------- Diagnoses ----------------
    diagnoses = []
    for enc in encounters:
        cat, fid = enc["category"], enc["facility_id"]
        if cat == "ob":
            primary, secondary_list = rng.choice(DX["ob_ip"]), DX["ob_secondary"]
        elif cat == "peds":
            primary, secondary_list = rng.choice(DX["child_ip"]), []
        elif enc["encounter_type"] == "Inpatient":
            primary = rng.choice(DX["ortho_ip"] if fid == 8 else DX["adult_ip"])
            secondary_list = DX["secondary"]
        elif cat == "emergency":
            primary, secondary_list = rng.choice(DX["emergency"]), DX["secondary"]
        else:
            primary, secondary_list = rng.choice(DX["outpatient"]), DX["secondary"]
        codes = [primary]
        if secondary_list:
            for code in rng.sample(secondary_list, k=min(len(secondary_list), rng.randint(0, 2))):
                if code not in codes:
                    codes.append(code)
        for rank, code in enumerate(codes, start=1):
            diagnoses.append(dict(encounter_id=enc["encounter_id"], icd10_code=code,
                                  diagnosis_rank=rank, is_primary=(rank == 1)))
    for i, d in enumerate(diagnoses, start=1):
        d["diagnosis_id"] = i

    # ---------------- Claims and denials ----------------
    aco = {f[0] for f in FACILITIES if f[4]}
    claims, denials = [], []
    for enc in encounters:
        if enc["status"] != "Completed":
            continue
        fid = enc["facility_id"]
        payer = patients[enc["patient_id"]]["primary_payer"]
        p_first, p_clean = PAYERS[payer]
        fast = rng.random() < (ACO_FAST_SHARE if fid in aco else NON_ACO_FAST_SHARE)
        lag = timedelta(hours=rng.randint(2, 23)) if fast else timedelta(hours=rng.randint(30, 240))
        submitted = enc["discharge_date"] + lag + timedelta(minutes=rng.randint(0, 59))

        has_denial = False
        if rng.random() < p_first:
            submission_count = 1
            if rng.random() < p_clean:
                status = "Paid"
            elif rng.random() < DENIAL_SHARE[fid]:
                has_denial = True
                status = "Paid" if rng.random() < 0.55 else "Denied"
            else:
                status = rng.choice(["Pending", "Partially Paid"])
        else:
            submission_count = rng.choice([2, 2, 3])
            if rng.random() < RESUBMIT_DENIAL.get(fid, RESUBMIT_DENIAL_DEFAULT):
                has_denial = True
                status = rng.choice(["Paid", "Denied"])
            else:
                status = "Paid"

        etype = enc["encounter_type"]
        billed = {"Inpatient": rng.uniform(8000, 45000), "Emergency": rng.uniform(600, 4000),
                  "Outpatient": rng.uniform(150, 1200)}[etype]
        paid = {"Paid": rng.uniform(0.55, 0.85), "Partially Paid": rng.uniform(0.2, 0.5),
                "Denied": 0.0, "Pending": 0.0}[status] * billed
        claim_id = len(claims) + 1
        claims.append(dict(claim_id=claim_id, encounter_id=enc["encounter_id"], payer_name=payer,
                           submitted_date=submitted, billed_amount=round(billed, 2),
                           paid_amount=round(paid, 2), claim_status=status,
                           submission_count=submission_count, has_denial=has_denial))
        if has_denial:
            for line in range(1, rng.choice([1, 1, 2, 3]) + 1):
                code, reason = rng.choice(CARC)
                denials.append(dict(claim_id=claim_id, line_number=line, carc_code=code,
                                    denial_reason=reason,
                                    denial_date=submitted + timedelta(days=rng.randint(7, 30)),
                                    appeal_status=("Overturned" if status == "Paid" else
                                                   rng.choice(["Upheld", "Not Appealed"]))))
    for i, d in enumerate(denials, start=1):
        d["denial_id"] = i

    # ---------------- Surveys ----------------
    surveys = []
    for enc in encounters:
        if enc["status"] != "Completed" or rng.random() > 0.35:
            continue
        rating = max(1, min(10, round(rng.gauss(SURVEY_MEAN[enc["facility_id"]], 0.8))))
        surveys.append(dict(survey_id=len(surveys) + 1, encounter_id=enc["encounter_id"],
                            facility_id=enc["facility_id"],
                            survey_date=(enc["discharge_date"] + timedelta(days=rng.randint(3, 20))).date().isoformat(),
                            overall_rating=rating))

    # Drop patients orphaned by readmission reassignment.
    used = {e["patient_id"] for e in encounters}
    patients = {k: v for k, v in patients.items() if k in used}

    write_csvs(patients, encounters, diagnoses, claims, denials, readmissions, surveys)
    golden = compute_answers(patients, encounters, diagnoses, claims, denials, readmissions, surveys, aco)
    GOLDEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN_FILE.write_text(json.dumps(golden, indent=2) + "\n")
    check_gates(golden)


def write_csvs(patients, encounters, diagnoses, claims, denials, readmissions, surveys):
    DATA_DIR.mkdir(parents=True, exist_ok=True)

    def write(name, header, rows):
        with open(DATA_DIR / f"{name}.csv", "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(header)
            w.writerows(rows)

    write("facilities", ["facility_id", "facility_name", "facility_type", "city", "state", "is_aco_participant"],
          [(f[0], f[1], f[2], f[3], "CO", str(f[4]).upper()) for f in FACILITIES])
    write("patients", ["patient_id", "dob", "sex", "zip_code"],
          [(p["patient_id"], p["dob"], p["sex"], p["zip_code"]) for p in sorted(patients.values(), key=lambda p: p["patient_id"])])
    write("encounters", ["encounter_id", "patient_id", "facility_id", "encounter_type", "admit_date", "discharge_date", "status"],
          [(e["encounter_id"], e["patient_id"], e["facility_id"], e["encounter_type"], fmt(e["admit_date"]),
            fmt(e["discharge_date"]), e["status"]) for e in encounters])
    write("diagnoses", ["diagnosis_id", "encounter_id", "icd10_code", "diagnosis_rank", "is_primary"],
          [(d["diagnosis_id"], d["encounter_id"], d["icd10_code"], d["diagnosis_rank"], str(d["is_primary"]).upper()) for d in diagnoses])
    write("claims", ["claim_id", "encounter_id", "payer_name", "submitted_date", "billed_amount", "paid_amount", "claim_status", "submission_count"],
          [(c["claim_id"], c["encounter_id"], c["payer_name"], fmt(c["submitted_date"]), f"{c['billed_amount']:.2f}",
            f"{c['paid_amount']:.2f}", c["claim_status"], c["submission_count"]) for c in claims])
    write("denials", ["denial_id", "claim_id", "line_number", "carc_code", "denial_reason", "denial_date", "appeal_status"],
          [(d["denial_id"], d["claim_id"], d["line_number"], d["carc_code"], d["denial_reason"],
            d["denial_date"].date().isoformat(), d["appeal_status"]) for d in denials])
    write("readmissions", ["readmission_id", "index_encounter_id", "readmit_encounter_id", "days_to_readmit", "is_planned"],
          [(r["readmission_id"], r["index_encounter_id"], r["readmit_encounter_id"], r["days_to_readmit"],
            str(r["is_planned"]).upper()) for r in sorted(readmissions, key=lambda r: r["readmission_id"])])
    write("patient_surveys", ["survey_id", "encounter_id", "facility_id", "survey_date", "overall_rating"],
          [(s["survey_id"], s["encounter_id"], s["facility_id"], s["survey_date"], s["overall_rating"]) for s in surveys])


def pct(n, d):
    return round(100.0 * n / d, 1) if d else None


def compute_answers(patients, encounters, diagnoses, claims, denials, readmissions, surveys, aco):
    """Compute every answer from the generated rows, the way answer_key.sql does."""
    fac_names = {f[0]: f[1] for f in FACILITIES}
    enc_by_id = {e["encounter_id"]: e for e in encounters}
    ob_encounters = {d["encounter_id"] for d in diagnoses if d["icd10_code"].startswith("O")}
    denied_claims = {d["claim_id"] for d in denials}

    def age_at(enc):
        dob = date.fromisoformat(patients[enc["patient_id"]]["dob"])
        return enc["admit_date"].year - dob.year   # matches DATEDIFF('year', dob, admit_date)

    inpatient = [e for e in encounters if e["encounter_type"] == "Inpatient"]
    base = [e for e in inpatient if e["status"] != "Cancelled" and e["discharge_date"] is not None]
    eligible = {e["encounter_id"] for e in base if age_at(e) >= 18 and e["encounter_id"] not in ob_encounters}
    numerator = [r for r in readmissions if not r["is_planned"] and r["days_to_readmit"] <= 30
                 and r["index_encounter_id"] in eligible]
    unplanned_all = [r for r in readmissions if not r["is_planned"]]

    # Each rule must matter: dropping it has to change the answer.
    no_30_day = [r for r in readmissions if not r["is_planned"] and r["index_encounter_id"] in eligible]
    with_cancelled = {e["encounter_id"] for e in inpatient if e["discharge_date"] is not None
                      and age_at(e) >= 18 and e["encounter_id"] not in ob_encounters}

    # Every repeat inpatient stay within 30 days must be recorded in READMISSIONS,
    # and no patient can be in two inpatient stays at once.
    recorded = {(r["index_encounter_id"], r["readmit_encounter_id"]) for r in readmissions}
    stays = defaultdict(list)
    for e in inpatient:
        if e["discharge_date"] is not None and e["status"] == "Completed":
            stays[e["patient_id"]].append(e)
    unrecorded = overlaps = 0
    for patient_stays in stays.values():
        patient_stays.sort(key=lambda e: e["admit_date"])
        for a, b in zip(patient_stays, patient_stays[1:]):
            if b["admit_date"] < a["discharge_date"]:
                overlaps += 1
            elif (b["admit_date"] - a["discharge_date"]).days <= 30 and (a["encounter_id"], b["encounter_id"]) not in recorded:
                unrecorded += 1

    # Per-facility readmission, denial rate and experience score.
    elig_by_fac, num_by_fac = defaultdict(int), defaultdict(int)
    for eid in eligible:
        elig_by_fac[enc_by_id[eid]["facility_id"]] += 1
    for r in numerator:
        num_by_fac[enc_by_id[r["index_encounter_id"]]["facility_id"]] += 1
    claims_by_fac, denied_by_fac = defaultdict(int), defaultdict(int)
    for c in claims:
        fid = enc_by_id[c["encounter_id"]]["facility_id"]
        claims_by_fac[fid] += 1
        denied_by_fac[fid] += c["claim_id"] in denied_claims
    ratings = defaultdict(list)
    for s in surveys:
        ratings[s["facility_id"]].append(s["overall_rating"])

    scorecard = {}
    for fid, *_ in FACILITIES:
        if not elig_by_fac[fid]:
            continue
        exp = round(10.0 * sum(ratings[fid]) / len(ratings[fid]), 1)
        readm = pct(num_by_fac[fid], elig_by_fac[fid])
        denial = pct(denied_by_fac[fid], claims_by_fac[fid])
        scorecard[fid] = dict(facility=fac_names[fid], experience_score=exp, readmission_rate=readm,
                              denial_rate=denial, eligible_index_admissions=elig_by_fac[fid],
                              passes=dict(experience=exp >= 85, readmission=readm < 8.0, denial=denial < 4.0))
    beacon = [fid for fid, s in scorecard.items() if all(s["passes"].values())]

    # Clean claims by payer.
    payer_tot, payer_naive, payer_clean = defaultdict(int), defaultdict(int), defaultdict(int)
    for c in claims:
        p = c["payer_name"]
        payer_tot[p] += 1
        payer_naive[p] += c["submission_count"] == 1
        payer_clean[p] += (c["submission_count"] == 1 and c["claim_status"] == "Paid"
                           and c["claim_id"] not in denied_claims)
    clean_by_payer = sorted(((p, pct(payer_clean[p], payer_tot[p])) for p in payer_tot), key=lambda x: -x[1])
    naive_by_payer = sorted(((p, pct(payer_naive[p], payer_tot[p])) for p in payer_tot), key=lambda x: -x[1])

    # Tailwind: submitted within 24 hours of discharge, ACO facilities, completed encounters.
    def tailwind(scope):
        hits = total = 0
        for c in claims:
            e = enc_by_id[c["encounter_id"]]
            if e["facility_id"] not in scope or e["status"] != "Completed" or e["discharge_date"] is None:
                continue
            total += 1
            hours = int((c["submitted_date"] - e["discharge_date"]).total_seconds() // 3600)
            hits += hours <= 24
        return hits, total

    tw_hits, tw_total = tailwind(aco)
    all_hits, all_total = tailwind({f[0] for f in FACILITIES})

    reporting = sorted(scorecard)
    suppressed = [fid for fid in reporting if elig_by_fac[fid] < 20]

    return {
        "routine_denial_rate": dict(denied_claims=len(denied_claims), total_claims=len(claims),
                                    rate=pct(len(denied_claims), len(claims)),
                                    naive_line_level_rate=pct(len(denials), len(claims))),
        "routine_aco_facilities": [fac_names[f] for f in sorted(aco)],
        "clean_claim_rate": dict(clean=sum(payer_clean.values()), total=len(claims),
                                 rate=pct(sum(payer_clean.values()), len(claims)),
                                 naive_rate=pct(sum(payer_naive.values()), len(claims)),
                                 by_payer=clean_by_payer, naive_by_payer=naive_by_payer),
        "readmission_rate": dict(numerator=len(numerator), eligible_index_admissions=len(eligible),
                                 rate=pct(len(numerator), len(eligible)),
                                 inpatient_encounters=len(inpatient),
                                 naive_unplanned_rate=pct(len(unplanned_all), len(inpatient)),
                                 naive_all_rate=pct(len(readmissions), len(inpatient)),
                                 rate_without_30_day_rule=pct(len(no_30_day), len(eligible)),
                                 eligible_if_cancelled_kept=len(with_cancelled),
                                 unrecorded_returns=unrecorded, overlapping_stays=overlaps),
        "beacon": dict(qualifying=[fac_names[f] for f in beacon], scorecard=scorecard),
        "tailwind": dict(hits=tw_hits, total=tw_total, rate=pct(tw_hits, tw_total),
                         all_facility_rate=pct(all_hits, all_total)),
        "release": dict(reporting_facilities=len(reporting), suppressed=[fac_names[f] for f in suppressed]),
    }


def check_gates(g):
    """Fail the run if any question stops discriminating."""
    failures = []

    def gate(name, ok):
        print(f"[{'PASS' if ok else 'FAIL'}] {name}")
        if not ok:
            failures.append(name)

    r = g["readmission_rate"]
    gate("readmission: correct rate below 14%", r["rate"] < 14.0)
    gate("readmission: naive unplanned rate above CMS 18%", r["naive_unplanned_rate"] > 18.0)
    gate("readmission: naive vs correct gap >= 6 points", r["naive_unplanned_rate"] - r["rate"] >= 6.0)
    gate("readmission: dropping the 30-day rule changes the rate", r["rate_without_30_day_rule"] > r["rate"])
    gate("readmission: dropping the cancelled rule changes the denominator",
         r["eligible_if_cancelled_kept"] > r["eligible_index_admissions"])
    gate("readmission: every repeat stay within 30 days is recorded", r["unrecorded_returns"] == 0)
    gate("readmission: no overlapping inpatient stays", r["overlapping_stays"] == 0)

    c = g["clean_claim_rate"]
    gate("clean claims: naive vs correct gap >= 20 points", c["naive_rate"] - c["rate"] >= 20.0)
    gate("clean claims: UnitedHealthcare tops the naive ranking", c["naive_by_payer"][0][0] == "UnitedHealthcare")
    correct_order = [p for p, _ in c["by_payer"]]
    gate("clean claims: UnitedHealthcare last on the correct ranking", correct_order[-1] == "UnitedHealthcare")

    b = g["beacon"]
    gate("BEACON: exactly Summit Orthopedic qualifies", b["qualifying"] == ["Summit Orthopedic Hospital"])
    sc = b["scorecard"]
    gate("BEACON: Cedar Ridge fails only readmission",
         sc[2]["passes"] == dict(experience=True, readmission=False, denial=True))
    gate("BEACON: Willow Creek fails only denial rate",
         sc[5]["passes"] == dict(experience=True, readmission=True, denial=False))

    t = g["tailwind"]
    gate("Tailwind: ACO rate narrowly below the 80% target", 74.0 <= t["rate"] < 80.0)
    gate("Tailwind: all-facility rate >= 25 points lower", t["rate"] - t["all_facility_rate"] >= 25.0)

    rel = g["release"]
    gate("release: three facilities suppressed",
         rel["suppressed"] == ["Granite Falls Hospital", "Sagebrush Regional Hospital",
                               "Juniper Valley Women's and Children's Hospital"])

    d = g["routine_denial_rate"]
    gate("routine denial rate: line-level count differs", d["naive_line_level_rate"] > d["rate"])

    # The expected answers in evals/questions.yaml are written by hand. Make sure they
    # still match what the data produces.
    yaml_text = (ROOT / "evals" / "questions.yaml").read_text()
    sc2, sc5 = sc[2], sc[5]
    expected = [
        f"{d['rate']}%", f"{d['denied_claims']} distinct denied claims", f"{d['total_claims']:,} claims",
        f"{d['naive_line_level_rate']}%",
        f"{c['rate']}% overall", f"{c['clean']:,} of {c['total']:,}", f"{c['naive_rate']}%",
        *[f"{p} {v}" for p, v in c["by_payer"]],
        f"{r['rate']}%", f"{r['numerator']} qualifying readmissions", f"{r['eligible_index_admissions']} eligible",
        f"all {r['inpatient_encounters']} inpatient", f"{r['naive_unplanned_rate']}%",
        f"readmission ({sc2['readmission_rate']}%)", f"denial rate ({sc5['denial_rate']}%)",
        f"{t['rate']}%", f"{t['hits']:,} of {t['total']:,}", f"{t['all_facility_rate']}%",
        f"{len(rel['suppressed'])} of the {rel['reporting_facilities']} reporting",
    ]
    stale = [e for e in expected if e not in yaml_text]
    gate("evals/questions.yaml matches the data", not stale)
    if stale:
        print("  missing from questions.yaml:", stale)

    if failures:
        raise SystemExit(f"{len(failures)} gate(s) failed")


if __name__ == "__main__":
    main()

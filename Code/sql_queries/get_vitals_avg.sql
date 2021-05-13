-- This computes the average of vital signs for each stay_id of a subject.
SELECT patient_vitals.subject_id
, patient_vitals.stay_id
, AVG(patient_vitals.heart_rate) as heart_rate_avg
, AVG(patient_vitals.sbp) as sbp_avg
, AVG(patient_vitals.mbp) as mbp_avg
, AVG(patient_vitals.dbp) as dbp_avg
, AVG(patient_vitals.sbp_ni) as sbp_ni_avg
, AVG(patient_vitals.mbp_ni) as mbp_ni_avg
, AVG(patient_vitals.dbp_ni) as dbp_ni_avg
, AVG(patient_vitals.temperature) as temperature_avg
, AVG(patient_vitals.glucose) as glucose_avg
, AVG(patient_vitals.spo2) as spo2_avg
, AVG(patient_vitals.resp_rate) as resp_rate_avg
FROM `physionet-data.mimic_derived.vitalsign` as patient_vitals
GROUP BY patient_vitals.stay_id, patient_vitals.subject_id

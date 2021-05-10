SELECT patient_vitals.subject_id
, patient_vitals.stay_id
, patient_vitals.heart_rate
, patient_vitals.sbp
, patient_vitals.mbp
, patient_vitals.dbp
, patient_vitals.sbp_ni
, patient_vitals.mbp_ni
, patient_vitals.dbp_ni
, patient_vitals.temperature
, patient_vitals.glucose
, patient_vitals.spo2
, patient_vitals.resp_rate
, patient_vitals.charttime 
, ROW_NUMBER() OVER
    (
        PARTITION BY patient_vitals.stay_id
        ORDER BY patient_vitals.charttime desc
    ) AS rn_charttime
FROM `physionet-data.mimic_derived.vitalsign` as patient_vitals
ORDER BY rn_charttime

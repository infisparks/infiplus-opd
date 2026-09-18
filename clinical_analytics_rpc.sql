-- ============================================================================
-- CLINICAL DATA ANALYTICS & INTELLIGENCE POSTGRESQL ENGINE FOR SUPABASE
-- ============================================================================

-- 1. PERFORMANCE INDEXES (Run once to supercharge query execution speed)
CREATE INDEX IF NOT EXISTS idx_opd_registration_analytics 
  ON opd_registration ("is_Deleted", created_at, hospital_name, uhid);

CREATE INDEX IF NOT EXISTS idx_opd_reg_symptoms_analytics 
  ON opd_reg_symptoms (opd_id, name);

CREATE INDEX IF NOT EXISTS idx_opd_reg_diagnosis_analytics 
  ON opd_reg_diagnosis (opd_id, name);

CREATE INDEX IF NOT EXISTS idx_opd_reg_rx_analytics 
  ON opd_reg_rx (opd_id, medicine_name);

CREATE INDEX IF NOT EXISTS idx_opd_reg_reports_analytics 
  ON opd_reg_reports (opd_id, report_type, item_name);

CREATE INDEX IF NOT EXISTS idx_patient_detail_uhid 
  ON patient_detail (uhid);


-- 2. PRODUCTION HIGH-PERFORMANCE ANALYTICS RPC FUNCTION (NO RECORD LIMITS)
CREATE OR REPLACE FUNCTION get_clinical_analytics(
  p_start_date TIMESTAMPTZ DEFAULT NULL,
  p_end_date TIMESTAMPTZ DEFAULT NULL,
  p_hospital TEXT DEFAULT NULL,
  p_medicines TEXT[] DEFAULT NULL,
  p_symptoms TEXT[] DEFAULT NULL,
  p_diagnoses TEXT[] DEFAULT NULL,
  p_investigations TEXT[] DEFAULT NULL,
  p_advices TEXT[] DEFAULT NULL,
  p_limit INT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result JSONB;
  v_start TIMESTAMPTZ;
  v_end TIMESTAMPTZ;
BEGIN
  -- Default to last 7 days if start and end dates are not provided
  v_start := COALESCE(p_start_date, (NOW() - INTERVAL '7 days'));
  v_end := COALESCE(p_end_date, NOW());

  WITH
  -- 1. Base Filtered OPD Visits
  filtered_opd AS (
    SELECT 
      opd.id AS opd_id,
      opd.uhid,
      opd.created_at,
      opd.hospital_name,
      opd.visit_type,
      opd.visit_status,
      opd.is_finalized,
      opd.treating_doctor_id,
      opd.clinical_data,
      pd.name AS patient_name,
      pd.gender AS patient_gender,
      pd.age AS patient_age,
      pd.age_unit AS patient_age_unit,
      pd.number AS patient_phone,
      pd.address AS patient_address
    FROM opd_registration opd
    LEFT JOIN patient_detail pd ON pd.uhid = opd.uhid
    WHERE (COALESCE(opd."is_Deleted", false) = false)
      AND opd.created_at >= v_start
      AND opd.created_at <= v_end
      AND (p_hospital IS NULL OR p_hospital = 'All Hospitals' OR opd.hospital_name = p_hospital)
      -- Optional: Medicines Filter Match
      AND (
        p_medicines IS NULL 
        OR CARDINALITY(p_medicines) = 0 
        OR EXISTS (
          SELECT 1 FROM opd_reg_rx rx 
          WHERE rx.opd_id = opd.id 
            AND rx.medicine_name ILIKE ANY (p_medicines)
        )
      )
      -- Optional: Symptoms Filter Match
      AND (
        p_symptoms IS NULL 
        OR CARDINALITY(p_symptoms) = 0 
        OR EXISTS (
          SELECT 1 FROM opd_reg_symptoms sym 
          WHERE sym.opd_id = opd.id 
            AND sym.name ILIKE ANY (p_symptoms)
        )
      )
      -- Optional: Diagnoses Filter Match
      AND (
        p_diagnoses IS NULL 
        OR CARDINALITY(p_diagnoses) = 0 
        OR EXISTS (
          SELECT 1 FROM opd_reg_diagnosis diag 
          WHERE diag.opd_id = opd.id 
            AND diag.name ILIKE ANY (p_diagnoses)
        )
      )
      -- Optional: Investigations Filter Match
      AND (
        p_investigations IS NULL 
        OR CARDINALITY(p_investigations) = 0 
        OR EXISTS (
          SELECT 1 FROM opd_reg_reports rep 
          WHERE rep.opd_id = opd.id 
            AND rep.report_type = 'investigation'
            AND rep.item_name ILIKE ANY (p_investigations)
        )
      )
      -- Optional: Advice / Instructions Filter Match
      AND (
        p_advices IS NULL 
        OR CARDINALITY(p_advices) = 0 
        OR EXISTS (
          SELECT 1 FROM opd_reg_reports rep 
          WHERE rep.opd_id = opd.id 
            AND rep.report_type IN ('instruction', 'procedure')
            AND rep.item_name ILIKE ANY (p_advices)
        )
      )
  ),

  -- 2. Daily Timeline Aggregations
  daily_stats AS (
    SELECT 
      TO_CHAR(DATE_TRUNC('day', created_at), 'YYYY-MM-DD') AS visit_day,
      COUNT(*)::INT AS count
    FROM filtered_opd
    GROUP BY DATE_TRUNC('day', created_at)
    ORDER BY DATE_TRUNC('day', created_at) ASC
  ),

  -- 3. Top Diagnoses
  top_diag AS (
    SELECT 
      d.name,
      COUNT(*)::INT AS count
    FROM opd_reg_diagnosis d
    INNER JOIN filtered_opd fo ON fo.opd_id = d.opd_id
    WHERE d.name IS NOT NULL AND TRIM(d.name) <> ''
    GROUP BY d.name
    ORDER BY count DESC
    LIMIT 10
  ),

  -- 4. Top Medicines
  top_rx AS (
    SELECT 
      rx.medicine_name AS name,
      COUNT(*)::INT AS count
    FROM opd_reg_rx rx
    INNER JOIN filtered_opd fo ON fo.opd_id = rx.opd_id
    WHERE rx.medicine_name IS NOT NULL AND TRIM(rx.medicine_name) <> ''
    GROUP BY rx.medicine_name
    ORDER BY count DESC
    LIMIT 10
  ),

  -- 5. Top Symptoms
  top_sym AS (
    SELECT 
      s.name,
      COUNT(*)::INT AS count
    FROM opd_reg_symptoms s
    INNER JOIN filtered_opd fo ON fo.opd_id = s.opd_id
    WHERE s.name IS NOT NULL AND TRIM(s.name) <> ''
    GROUP BY s.name
    ORDER BY count DESC
    LIMIT 10
  ),

  -- 6. Top Investigations / Blood Tests
  top_inv AS (
    SELECT 
      rep.item_name AS name,
      COUNT(*)::INT AS count
    FROM opd_reg_reports rep
    INNER JOIN filtered_opd fo ON fo.opd_id = rep.opd_id
    WHERE rep.report_type = 'investigation'
      AND rep.item_name IS NOT NULL AND TRIM(rep.item_name) <> ''
    GROUP BY rep.item_name
    ORDER BY count DESC
    LIMIT 10
  ),

  -- 7. Aggregated Demographics & Totals
  summary_metrics AS (
    SELECT 
      COUNT(*)::INT AS total_visits,
      COUNT(DISTINCT uhid)::INT AS unique_patients,
      COALESCE(ROUND(AVG(NULLIF(regexp_replace(patient_age::text, '[^0-9]', '', 'g'), '')::NUMERIC), 1), 0) AS avg_age,
      COUNT(*) FILTER (WHERE UPPER(patient_gender) IN ('M', 'MALE'))::INT AS male_count,
      COUNT(*) FILTER (WHERE UPPER(patient_gender) IN ('F', 'FEMALE'))::INT AS female_count,
      COUNT(*) FILTER (WHERE UPPER(patient_gender) NOT IN ('M', 'MALE', 'F', 'FEMALE') OR patient_gender IS NULL)::INT AS other_count
    FROM filtered_opd
  ),

  -- 8. Detailed Patient Records with Joined Nested Arrays (ALL RECORDS RETURNED)
  records_payload AS (
    SELECT 
      fo.opd_id,
      fo.uhid,
      fo.created_at,
      fo.hospital_name,
      fo.visit_type,
      fo.visit_status,
      fo.is_finalized,
      fo.treating_doctor_id,
      COALESCE(fo.patient_name, 'Unknown') AS patient_name,
      COALESCE(fo.patient_gender, 'U') AS gender,
      COALESCE(fo.patient_age::text, '0') AS age,
      COALESCE(fo.patient_age_unit, 'Y') AS age_unit,
      COALESCE(fo.patient_phone::text, 'N/A') AS phone,
      COALESCE(fo.patient_address, '') AS address,
      
      -- Subquery for Symptoms
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'name', sym.name,
          'note', sym.note,
          'duration', sym.duration,
          'severity', sym.severity
        ))
        FROM opd_reg_symptoms sym
        WHERE sym.opd_id = fo.opd_id
      ), '[]'::jsonb) AS symptoms,

      -- Subquery for Diagnoses
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'name', diag.name,
          'note', diag.note
        ))
        FROM opd_reg_diagnosis diag
        WHERE diag.opd_id = fo.opd_id
      ), '[]'::jsonb) AS diagnoses,

      -- Subquery for Rx / Prescriptions
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'name', rx.medicine_name,
          'type', rx.medicine_type,
          'unit', rx.unit,
          'dosage', rx.dosage,
          'duration', rx.duration,
          'timing', rx.timing_json,
          'note', rx.note
        ))
        FROM opd_reg_rx rx
        WHERE rx.opd_id = fo.opd_id
      ), '[]'::jsonb) AS medicines,

      -- Subquery for Reports (Investigations, Instructions, Procedures)
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'item_name', rep.item_name,
          'report_type', rep.report_type
        ))
        FROM opd_reg_reports rep
        WHERE rep.opd_id = fo.opd_id
      ), '[]'::jsonb) AS reports,

      fo.clinical_data
    FROM filtered_opd fo
    ORDER BY fo.created_at DESC
    LIMIT p_limit
  )

  -- Final Unified Response Assembly
  SELECT jsonb_build_object(
    'summary', (SELECT row_to_json(summary_metrics.*) FROM summary_metrics),
    'daily_trends', COALESCE((SELECT jsonb_agg(daily_stats.*) FROM daily_stats), '[]'::jsonb),
    'top_diagnoses', COALESCE((SELECT jsonb_agg(top_diag.*) FROM top_diag), '[]'::jsonb),
    'top_medicines', COALESCE((SELECT jsonb_agg(top_rx.*) FROM top_rx), '[]'::jsonb),
    'top_symptoms', COALESCE((SELECT jsonb_agg(top_sym.*) FROM top_sym), '[]'::jsonb),
    'top_investigations', COALESCE((SELECT jsonb_agg(top_inv.*) FROM top_inv), '[]'::jsonb),
    'records', COALESCE((SELECT jsonb_agg(records_payload.*) FROM records_payload), '[]'::jsonb)
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

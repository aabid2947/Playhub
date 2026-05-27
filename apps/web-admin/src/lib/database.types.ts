export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      academies: {
        Row: {
          address: string | null
          city: string | null
          created_at: string
          email: string | null
          holidays: string[]
          hours_close: string | null
          hours_open: string | null
          id: string
          invoice_prefix: string
          is_active: boolean
          logo: string | null
          name: string
          owner_id: string | null
          phone: string | null
          pincode: string | null
          settings: Json
          state: string | null
          subscription_status: Database["public"]["Enums"]["subscription_status"]
          trial_ends_at: string | null
          updated_at: string
          website: string | null
        }
        Insert: {
          address?: string | null
          city?: string | null
          created_at?: string
          email?: string | null
          holidays?: string[]
          hours_close?: string | null
          hours_open?: string | null
          id?: string
          invoice_prefix?: string
          is_active?: boolean
          logo?: string | null
          name: string
          owner_id?: string | null
          phone?: string | null
          pincode?: string | null
          settings?: Json
          state?: string | null
          subscription_status?: Database["public"]["Enums"]["subscription_status"]
          trial_ends_at?: string | null
          updated_at?: string
          website?: string | null
        }
        Update: {
          address?: string | null
          city?: string | null
          created_at?: string
          email?: string | null
          holidays?: string[]
          hours_close?: string | null
          hours_open?: string | null
          id?: string
          invoice_prefix?: string
          is_active?: boolean
          logo?: string | null
          name?: string
          owner_id?: string | null
          phone?: string | null
          pincode?: string | null
          settings?: Json
          state?: string | null
          subscription_status?: Database["public"]["Enums"]["subscription_status"]
          trial_ends_at?: string | null
          updated_at?: string
          website?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "academies_owner_fk"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      academy_invoice_counters: {
        Row: {
          academy_id: string
          next_value: number
        }
        Insert: {
          academy_id: string
          next_value?: number
        }
        Update: {
          academy_id?: string
          next_value?: number
        }
        Relationships: [
          {
            foreignKeyName: "academy_invoice_counters_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: true
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      academy_subscriptions: {
        Row: {
          academy_id: string
          billing_cycle: string
          cancellation_reason: string | null
          cancelled_at: string | null
          created_at: string
          current_period_end: string
          current_period_start: string
          id: string
          plan_id: string
          razorpay_customer_id: string | null
          razorpay_subscription_id: string | null
          status: Database["public"]["Enums"]["subscription_status"]
          trial_ends_at: string | null
          updated_at: string
        }
        Insert: {
          academy_id: string
          billing_cycle?: string
          cancellation_reason?: string | null
          cancelled_at?: string | null
          created_at?: string
          current_period_end?: string
          current_period_start?: string
          id?: string
          plan_id: string
          razorpay_customer_id?: string | null
          razorpay_subscription_id?: string | null
          status?: Database["public"]["Enums"]["subscription_status"]
          trial_ends_at?: string | null
          updated_at?: string
        }
        Update: {
          academy_id?: string
          billing_cycle?: string
          cancellation_reason?: string | null
          cancelled_at?: string | null
          created_at?: string
          current_period_end?: string
          current_period_start?: string
          id?: string
          plan_id?: string
          razorpay_customer_id?: string | null
          razorpay_subscription_id?: string | null
          status?: Database["public"]["Enums"]["subscription_status"]
          trial_ends_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "academy_subscriptions_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: true
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "academy_subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "subscription_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      announcement_recipients: {
        Row: {
          academy_id: string
          announcement_id: string
          delivered_at: string
          id: string
          read_at: string | null
          user_id: string
        }
        Insert: {
          academy_id: string
          announcement_id: string
          delivered_at?: string
          id?: string
          read_at?: string | null
          user_id: string
        }
        Update: {
          academy_id?: string
          announcement_id?: string
          delivered_at?: string
          id?: string
          read_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "announcement_recipients_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcement_recipients_announcement_id_fkey"
            columns: ["announcement_id"]
            isOneToOne: false
            referencedRelation: "announcements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcement_recipients_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      announcements: {
        Row: {
          academy_id: string
          body: string
          body_html: string | null
          created_at: string
          created_by: string | null
          failed_count: number | null
          id: string
          scheduled_for: string | null
          sent_at: string | null
          sent_count: number | null
          subject: string
          target_batches: string[]
          target_centers: string[]
          target_roles: Database["public"]["Enums"]["user_role"][]
          updated_at: string
          via_email: boolean
          via_in_app: boolean
          via_push: boolean
        }
        Insert: {
          academy_id: string
          body: string
          body_html?: string | null
          created_at?: string
          created_by?: string | null
          failed_count?: number | null
          id?: string
          scheduled_for?: string | null
          sent_at?: string | null
          sent_count?: number | null
          subject: string
          target_batches?: string[]
          target_centers?: string[]
          target_roles?: Database["public"]["Enums"]["user_role"][]
          updated_at?: string
          via_email?: boolean
          via_in_app?: boolean
          via_push?: boolean
        }
        Update: {
          academy_id?: string
          body?: string
          body_html?: string | null
          created_at?: string
          created_by?: string | null
          failed_count?: number | null
          id?: string
          scheduled_for?: string | null
          sent_at?: string | null
          sent_count?: number | null
          subject?: string
          target_batches?: string[]
          target_centers?: string[]
          target_roles?: Database["public"]["Enums"]["user_role"][]
          updated_at?: string
          via_email?: boolean
          via_in_app?: boolean
          via_push?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "announcements_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      attendance_records: {
        Row: {
          academy_id: string
          batch_id: string
          check_in_time: string | null
          check_out_time: string | null
          coach_id: string | null
          created_at: string
          date: string
          id: string
          marked_by: string | null
          method: string
          notes: string | null
          status: string
          student_id: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          batch_id: string
          check_in_time?: string | null
          check_out_time?: string | null
          coach_id?: string | null
          created_at?: string
          date: string
          id?: string
          marked_by?: string | null
          method?: string
          notes?: string | null
          status: string
          student_id: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          batch_id?: string
          check_in_time?: string | null
          check_out_time?: string | null
          coach_id?: string | null
          created_at?: string
          date?: string
          id?: string
          marked_by?: string | null
          method?: string
          notes?: string | null
          status?: string
          student_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "attendance_records_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "analytics_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "attendance_records_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches_with_counts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "mv_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "attendance_records_coach_id_fkey"
            columns: ["coach_id"]
            isOneToOne: false
            referencedRelation: "coaches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_marked_by_fkey"
            columns: ["marked_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attendance_records_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "attendance_records_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "attendance_records_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_logs: {
        Row: {
          academy_id: string | null
          action: string
          after: Json | null
          before: Json | null
          created_at: string
          entity_id: string | null
          entity_type: string
          id: string
          user_id: string | null
        }
        Insert: {
          academy_id?: string | null
          action: string
          after?: Json | null
          before?: Json | null
          created_at?: string
          entity_id?: string | null
          entity_type: string
          id?: string
          user_id?: string | null
        }
        Update: {
          academy_id?: string | null
          action?: string
          after?: Json | null
          before?: Json | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string
          id?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_logs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      batch_discount_assignments: {
        Row: {
          academy_id: string
          batch_id: string
          created_at: string
          discount_structure_id: string
          end_date: string | null
          id: string
          is_active: boolean
          start_date: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          batch_id: string
          created_at?: string
          discount_structure_id: string
          end_date?: string | null
          id?: string
          is_active?: boolean
          start_date?: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          batch_id?: string
          created_at?: string
          discount_structure_id?: string
          end_date?: string | null
          id?: string
          is_active?: boolean
          start_date?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "batch_discount_assignments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batch_discount_assignments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "analytics_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "batch_discount_assignments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batch_discount_assignments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches_with_counts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batch_discount_assignments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "mv_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "batch_discount_assignments_discount_structure_id_fkey"
            columns: ["discount_structure_id"]
            isOneToOne: false
            referencedRelation: "discount_structures"
            referencedColumns: ["id"]
          },
        ]
      }
      batch_enrollments: {
        Row: {
          academy_id: string
          batch_id: string
          enrolled_at: string
          enrollment_status: string
          id: string
          student_id: string
        }
        Insert: {
          academy_id: string
          batch_id: string
          enrolled_at?: string
          enrollment_status?: string
          id?: string
          student_id: string
        }
        Update: {
          academy_id?: string
          batch_id?: string
          enrolled_at?: string
          enrollment_status?: string
          id?: string
          student_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "batch_enrollments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batch_enrollments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "analytics_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "batch_enrollments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batch_enrollments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches_with_counts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batch_enrollments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "mv_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "batch_enrollments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "batch_enrollments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "batch_enrollments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      batch_fee_assignments: {
        Row: {
          academy_id: string
          batch_id: string
          billing_day: number | null
          created_at: string
          end_date: string | null
          fee_structure_id: string
          id: string
          is_active: boolean
          start_date: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          batch_id: string
          billing_day?: number | null
          created_at?: string
          end_date?: string | null
          fee_structure_id: string
          id?: string
          is_active?: boolean
          start_date?: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          batch_id?: string
          billing_day?: number | null
          created_at?: string
          end_date?: string | null
          fee_structure_id?: string
          id?: string
          is_active?: boolean
          start_date?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "batch_fee_assignments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batch_fee_assignments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "analytics_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "batch_fee_assignments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batch_fee_assignments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches_with_counts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batch_fee_assignments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "mv_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "batch_fee_assignments_fee_structure_id_fkey"
            columns: ["fee_structure_id"]
            isOneToOne: false
            referencedRelation: "fee_structures"
            referencedColumns: ["id"]
          },
        ]
      }
      batches: {
        Row: {
          academy_id: string
          age_group: string | null
          capacity: number | null
          center_id: string | null
          coach_id: string | null
          created_at: string
          description: string | null
          end_date: string | null
          id: string
          is_active: boolean
          name: string
          schedule: Json
          skill_level: string | null
          sport_id: string | null
          start_date: string | null
          updated_at: string
        }
        Insert: {
          academy_id: string
          age_group?: string | null
          capacity?: number | null
          center_id?: string | null
          coach_id?: string | null
          created_at?: string
          description?: string | null
          end_date?: string | null
          id?: string
          is_active?: boolean
          name: string
          schedule?: Json
          skill_level?: string | null
          sport_id?: string | null
          start_date?: string | null
          updated_at?: string
        }
        Update: {
          academy_id?: string
          age_group?: string | null
          capacity?: number | null
          center_id?: string | null
          coach_id?: string | null
          created_at?: string
          description?: string | null
          end_date?: string | null
          id?: string
          is_active?: boolean
          name?: string
          schedule?: Json
          skill_level?: string | null
          sport_id?: string | null
          start_date?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "batches_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batches_center_id_fkey"
            columns: ["center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batches_coach_id_fkey"
            columns: ["coach_id"]
            isOneToOne: false
            referencedRelation: "coaches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batches_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      center_sports: {
        Row: {
          academy_id: string
          center_id: string
          created_at: string
          custom_name: string | null
          id: string
          is_active: boolean
          sport_id: string
        }
        Insert: {
          academy_id: string
          center_id: string
          created_at?: string
          custom_name?: string | null
          id?: string
          is_active?: boolean
          sport_id: string
        }
        Update: {
          academy_id?: string
          center_id?: string
          created_at?: string
          custom_name?: string | null
          id?: string
          is_active?: boolean
          sport_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "center_sports_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "center_sports_center_id_fkey"
            columns: ["center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "center_sports_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      centers: {
        Row: {
          academy_id: string
          address: string | null
          admin_id: string | null
          city: string | null
          created_at: string
          email: string | null
          facilities: string[]
          id: string
          is_active: boolean
          name: string
          phone: string | null
          pincode: string | null
          state: string | null
          updated_at: string
        }
        Insert: {
          academy_id: string
          address?: string | null
          admin_id?: string | null
          city?: string | null
          created_at?: string
          email?: string | null
          facilities?: string[]
          id?: string
          is_active?: boolean
          name: string
          phone?: string | null
          pincode?: string | null
          state?: string | null
          updated_at?: string
        }
        Update: {
          academy_id?: string
          address?: string | null
          admin_id?: string | null
          city?: string | null
          created_at?: string
          email?: string | null
          facilities?: string[]
          id?: string
          is_active?: boolean
          name?: string
          phone?: string | null
          pincode?: string | null
          state?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "centers_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "centers_admin_id_fkey"
            columns: ["admin_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      coach_documents: {
        Row: {
          academy_id: string
          coach_id: string
          file_path: string
          id: string
          mime_type: string | null
          original_filename: string | null
          size_bytes: number | null
          type: string
          uploaded_at: string
          uploaded_by: string | null
        }
        Insert: {
          academy_id: string
          coach_id: string
          file_path: string
          id?: string
          mime_type?: string | null
          original_filename?: string | null
          size_bytes?: number | null
          type: string
          uploaded_at?: string
          uploaded_by?: string | null
        }
        Update: {
          academy_id?: string
          coach_id?: string
          file_path?: string
          id?: string
          mime_type?: string | null
          original_filename?: string | null
          size_bytes?: number | null
          type?: string
          uploaded_at?: string
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "coach_documents_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coach_documents_coach_id_fkey"
            columns: ["coach_id"]
            isOneToOne: false
            referencedRelation: "coaches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coach_documents_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      coach_sports: {
        Row: {
          academy_id: string
          coach_id: string
          created_at: string
          id: string
          is_primary: boolean
          sport_id: string
        }
        Insert: {
          academy_id: string
          coach_id: string
          created_at?: string
          id?: string
          is_primary?: boolean
          sport_id: string
        }
        Update: {
          academy_id?: string
          coach_id?: string
          created_at?: string
          id?: string
          is_primary?: boolean
          sport_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "coach_sports_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coach_sports_coach_id_fkey"
            columns: ["coach_id"]
            isOneToOne: false
            referencedRelation: "coaches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coach_sports_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      coaches: {
        Row: {
          academy_id: string
          center_id: string | null
          certifications: string[]
          created_at: string
          email: string | null
          experience_years: number | null
          first_name: string
          id: string
          is_active: boolean
          join_date: string
          last_name: string
          payment_type: string | null
          phone: string | null
          photo: string | null
          qualifications: string[]
          salary: number | null
          specialization: string[]
          updated_at: string
          user_id: string | null
        }
        Insert: {
          academy_id: string
          center_id?: string | null
          certifications?: string[]
          created_at?: string
          email?: string | null
          experience_years?: number | null
          first_name: string
          id?: string
          is_active?: boolean
          join_date?: string
          last_name: string
          payment_type?: string | null
          phone?: string | null
          photo?: string | null
          qualifications?: string[]
          salary?: number | null
          specialization?: string[]
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          academy_id?: string
          center_id?: string | null
          certifications?: string[]
          created_at?: string
          email?: string | null
          experience_years?: number | null
          first_name?: string
          id?: string
          is_active?: boolean
          join_date?: string
          last_name?: string
          payment_type?: string | null
          phone?: string | null
          photo?: string | null
          qualifications?: string[]
          salary?: number | null
          specialization?: string[]
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "coaches_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coaches_center_id_fkey"
            columns: ["center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "coaches_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      device_tokens: {
        Row: {
          academy_id: string | null
          app_version: string | null
          created_at: string
          device_id: string | null
          fcm_token: string
          id: string
          last_seen_at: string
          platform: string
          user_id: string
        }
        Insert: {
          academy_id?: string | null
          app_version?: string | null
          created_at?: string
          device_id?: string | null
          fcm_token: string
          id?: string
          last_seen_at?: string
          platform: string
          user_id: string
        }
        Update: {
          academy_id?: string | null
          app_version?: string | null
          created_at?: string
          device_id?: string | null
          fcm_token?: string
          id?: string
          last_seen_at?: string
          platform?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "device_tokens_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "device_tokens_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      discount_structures: {
        Row: {
          academy_id: string
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          type: string
          updated_at: string
          value: number
        }
        Insert: {
          academy_id: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          type: string
          updated_at?: string
          value: number
        }
        Update: {
          academy_id?: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          type?: string
          updated_at?: string
          value?: number
        }
        Relationships: [
          {
            foreignKeyName: "discount_structures_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      event_registrations: {
        Row: {
          academy_id: string
          cancelled_at: string | null
          event_id: string
          fee_paid: boolean
          id: string
          invoice_id: string | null
          notes: string | null
          registered_at: string
          registered_by: string | null
          status: string
          student_id: string
        }
        Insert: {
          academy_id: string
          cancelled_at?: string | null
          event_id: string
          fee_paid?: boolean
          id?: string
          invoice_id?: string | null
          notes?: string | null
          registered_at?: string
          registered_by?: string | null
          status?: string
          student_id: string
        }
        Update: {
          academy_id?: string
          cancelled_at?: string | null
          event_id?: string
          fee_paid?: boolean
          id?: string
          invoice_id?: string | null
          notes?: string | null
          registered_at?: string
          registered_by?: string | null
          status?: string
          student_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_registrations_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "event_registrations_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "event_registrations_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      event_results: {
        Row: {
          academy_id: string
          category: string | null
          certificate_issued_at: string | null
          certificate_url: string | null
          created_at: string
          event_id: string
          id: string
          placement: number | null
          recorded_by: string | null
          registration_id: string | null
          remarks: string | null
          score: number | null
          student_id: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          category?: string | null
          certificate_issued_at?: string | null
          certificate_url?: string | null
          created_at?: string
          event_id: string
          id?: string
          placement?: number | null
          recorded_by?: string | null
          registration_id?: string | null
          remarks?: string | null
          score?: number | null
          student_id: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          category?: string | null
          certificate_issued_at?: string | null
          certificate_url?: string | null
          created_at?: string
          event_id?: string
          id?: string
          placement?: number | null
          recorded_by?: string | null
          registration_id?: string | null
          remarks?: string | null
          score?: number | null
          student_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_results_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_results_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_results_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_results_registration_id_fkey"
            columns: ["registration_id"]
            isOneToOne: false
            referencedRelation: "event_registrations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_results_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "event_results_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "event_results_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      events: {
        Row: {
          academy_id: string
          capacity: number | null
          center_id: string | null
          certificate_template_url: string | null
          created_at: string
          created_by: string | null
          description: string | null
          eligible_batch_ids: string[]
          ends_at: string | null
          fee_amount: number
          id: string
          kind: Database["public"]["Enums"]["event_kind"]
          location: string | null
          registration_closes_at: string | null
          registration_opens_at: string | null
          sport_id: string | null
          starts_at: string
          status: Database["public"]["Enums"]["event_status"]
          title: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          capacity?: number | null
          center_id?: string | null
          certificate_template_url?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          eligible_batch_ids?: string[]
          ends_at?: string | null
          fee_amount?: number
          id?: string
          kind?: Database["public"]["Enums"]["event_kind"]
          location?: string | null
          registration_closes_at?: string | null
          registration_opens_at?: string | null
          sport_id?: string | null
          starts_at: string
          status?: Database["public"]["Enums"]["event_status"]
          title: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          capacity?: number | null
          center_id?: string | null
          certificate_template_url?: string | null
          created_at?: string
          created_by?: string | null
          description?: string | null
          eligible_batch_ids?: string[]
          ends_at?: string | null
          fee_amount?: number
          id?: string
          kind?: Database["public"]["Enums"]["event_kind"]
          location?: string | null
          registration_closes_at?: string | null
          registration_opens_at?: string | null
          sport_id?: string | null
          starts_at?: string
          status?: Database["public"]["Enums"]["event_status"]
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "events_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_center_id_fkey"
            columns: ["center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "events_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      fee_structures: {
        Row: {
          academy_id: string
          base_amount: number
          batch_id: string | null
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          late_fee_flat: number | null
          late_fee_grace_days: number
          late_fee_pct: number | null
          late_fee_policy: string
          name: string
          sport_id: string | null
          tax_pct: number
          type: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          base_amount: number
          batch_id?: string | null
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          late_fee_flat?: number | null
          late_fee_grace_days?: number
          late_fee_pct?: number | null
          late_fee_policy?: string
          name: string
          sport_id?: string | null
          tax_pct?: number
          type: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          base_amount?: number
          batch_id?: string | null
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          late_fee_flat?: number | null
          late_fee_grace_days?: number
          late_fee_pct?: number | null
          late_fee_policy?: string
          name?: string
          sport_id?: string | null
          tax_pct?: number
          type?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "fee_structures_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fee_structures_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "analytics_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "fee_structures_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fee_structures_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches_with_counts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fee_structures_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "mv_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "fee_structures_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_categories: {
        Row: {
          academy_id: string
          created_at: string
          description: string | null
          id: string
          name: string
        }
        Insert: {
          academy_id: string
          created_at?: string
          description?: string | null
          id?: string
          name: string
        }
        Update: {
          academy_id?: string
          created_at?: string
          description?: string | null
          id?: string
          name?: string
        }
        Relationships: [
          {
            foreignKeyName: "inventory_categories_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_items: {
        Row: {
          academy_id: string
          category_id: string | null
          center_id: string | null
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          on_hand: number
          reorder_threshold: number
          sku: string | null
          unit: string
          unit_cost: number
          updated_at: string
          vendor_id: string | null
        }
        Insert: {
          academy_id: string
          category_id?: string | null
          center_id?: string | null
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          on_hand?: number
          reorder_threshold?: number
          sku?: string | null
          unit?: string
          unit_cost?: number
          updated_at?: string
          vendor_id?: string | null
        }
        Update: {
          academy_id?: string
          category_id?: string | null
          center_id?: string | null
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          on_hand?: number
          reorder_threshold?: number
          sku?: string | null
          unit?: string
          unit_cost?: number
          updated_at?: string
          vendor_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_items_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_items_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "inventory_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_items_center_id_fkey"
            columns: ["center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_items_vendor_id_fkey"
            columns: ["vendor_id"]
            isOneToOne: false
            referencedRelation: "vendors"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_movements: {
        Row: {
          academy_id: string
          coach_id: string | null
          id: string
          item_id: string
          kind: string
          notes: string | null
          performed_at: string
          performed_by: string | null
          qty: number
          reference: string | null
          student_id: string | null
          unit_cost: number | null
          vendor_id: string | null
        }
        Insert: {
          academy_id: string
          coach_id?: string | null
          id?: string
          item_id: string
          kind: string
          notes?: string | null
          performed_at?: string
          performed_by?: string | null
          qty: number
          reference?: string | null
          student_id?: string | null
          unit_cost?: number | null
          vendor_id?: string | null
        }
        Update: {
          academy_id?: string
          coach_id?: string | null
          id?: string
          item_id?: string
          kind?: string
          notes?: string | null
          performed_at?: string
          performed_by?: string | null
          qty?: number
          reference?: string | null
          student_id?: string | null
          unit_cost?: number | null
          vendor_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_movements_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_coach_id_fkey"
            columns: ["coach_id"]
            isOneToOne: false
            referencedRelation: "coaches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "inventory_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_performed_by_fkey"
            columns: ["performed_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "inventory_movements_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "inventory_movements_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_vendor_id_fkey"
            columns: ["vendor_id"]
            isOneToOne: false
            referencedRelation: "vendors"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_line_items: {
        Row: {
          academy_id: string
          created_at: string
          description: string
          id: string
          invoice_id: string
          kind: string
          quantity: number
          total_amount: number | null
          unit_amount: number
        }
        Insert: {
          academy_id: string
          created_at?: string
          description: string
          id?: string
          invoice_id: string
          kind: string
          quantity?: number
          total_amount?: number | null
          unit_amount: number
        }
        Update: {
          academy_id?: string
          created_at?: string
          description?: string
          id?: string
          invoice_id?: string
          kind?: string
          quantity?: number
          total_amount?: number | null
          unit_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "invoice_line_items_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoice_line_items_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      invoices: {
        Row: {
          academy_id: string
          amount: number | null
          amount_paid: number
          base_amount: number
          created_at: string
          discount_amount: number
          due_date: string
          fee_structure_id: string | null
          id: string
          invoice_number: string
          issued_at: string
          late_fee_amount: number
          notes: string | null
          period_end: string | null
          period_start: string | null
          status: string
          student_id: string
          tax_amount: number
          updated_at: string
        }
        Insert: {
          academy_id: string
          amount?: number | null
          amount_paid?: number
          base_amount: number
          created_at?: string
          discount_amount?: number
          due_date: string
          fee_structure_id?: string | null
          id?: string
          invoice_number: string
          issued_at?: string
          late_fee_amount?: number
          notes?: string | null
          period_end?: string | null
          period_start?: string | null
          status?: string
          student_id: string
          tax_amount?: number
          updated_at?: string
        }
        Update: {
          academy_id?: string
          amount?: number | null
          amount_paid?: number
          base_amount?: number
          created_at?: string
          discount_amount?: number
          due_date?: string
          fee_structure_id?: string | null
          id?: string
          invoice_number?: string
          issued_at?: string
          late_fee_amount?: number
          notes?: string | null
          period_end?: string | null
          period_start?: string | null
          status?: string
          student_id?: string
          tax_amount?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "invoices_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_fee_structure_id_fkey"
            columns: ["fee_structure_id"]
            isOneToOne: false
            referencedRelation: "fee_structures"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invoices_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "invoices_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "invoices_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      lead_activities: {
        Row: {
          academy_id: string
          content: string | null
          created_at: string
          id: string
          kind: string
          lead_id: string
          metadata: Json
          user_id: string | null
        }
        Insert: {
          academy_id: string
          content?: string | null
          created_at?: string
          id?: string
          kind: string
          lead_id: string
          metadata?: Json
          user_id?: string | null
        }
        Update: {
          academy_id?: string
          content?: string | null
          created_at?: string
          id?: string
          kind?: string
          lead_id?: string
          metadata?: Json
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "lead_activities_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_activities_lead_id_fkey"
            columns: ["lead_id"]
            isOneToOne: false
            referencedRelation: "leads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "lead_activities_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      leads: {
        Row: {
          academy_id: string
          age: number | null
          assigned_to: string | null
          converted_at: string | null
          converted_student_id: string | null
          created_at: string
          email: string | null
          first_name: string
          id: string
          last_name: string | null
          lost_reason: string | null
          next_followup_at: string | null
          notes: string | null
          parent_name: string | null
          phone: string | null
          preferred_center_id: string | null
          source: Database["public"]["Enums"]["lead_source"]
          sport_id: string | null
          status: Database["public"]["Enums"]["lead_status"]
          trial_scheduled_at: string | null
          updated_at: string
        }
        Insert: {
          academy_id: string
          age?: number | null
          assigned_to?: string | null
          converted_at?: string | null
          converted_student_id?: string | null
          created_at?: string
          email?: string | null
          first_name: string
          id?: string
          last_name?: string | null
          lost_reason?: string | null
          next_followup_at?: string | null
          notes?: string | null
          parent_name?: string | null
          phone?: string | null
          preferred_center_id?: string | null
          source?: Database["public"]["Enums"]["lead_source"]
          sport_id?: string | null
          status?: Database["public"]["Enums"]["lead_status"]
          trial_scheduled_at?: string | null
          updated_at?: string
        }
        Update: {
          academy_id?: string
          age?: number | null
          assigned_to?: string | null
          converted_at?: string | null
          converted_student_id?: string | null
          created_at?: string
          email?: string | null
          first_name?: string
          id?: string
          last_name?: string | null
          lost_reason?: string | null
          next_followup_at?: string | null
          notes?: string | null
          parent_name?: string | null
          phone?: string | null
          preferred_center_id?: string | null
          source?: Database["public"]["Enums"]["lead_source"]
          sport_id?: string | null
          status?: Database["public"]["Enums"]["lead_status"]
          trial_scheduled_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "leads_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leads_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leads_converted_student_id_fkey"
            columns: ["converted_student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "leads_converted_student_id_fkey"
            columns: ["converted_student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "leads_converted_student_id_fkey"
            columns: ["converted_student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leads_preferred_center_id_fkey"
            columns: ["preferred_center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "leads_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      message_threads: {
        Row: {
          academy_id: string
          batch_id: string | null
          created_at: string
          created_by: string | null
          direct_user_a: string | null
          direct_user_b: string | null
          id: string
          kind: Database["public"]["Enums"]["thread_kind"]
          last_message_at: string | null
          last_message_preview: string | null
          title: string | null
          updated_at: string
        }
        Insert: {
          academy_id: string
          batch_id?: string | null
          created_at?: string
          created_by?: string | null
          direct_user_a?: string | null
          direct_user_b?: string | null
          id?: string
          kind: Database["public"]["Enums"]["thread_kind"]
          last_message_at?: string | null
          last_message_preview?: string | null
          title?: string | null
          updated_at?: string
        }
        Update: {
          academy_id?: string
          batch_id?: string | null
          created_at?: string
          created_by?: string | null
          direct_user_a?: string | null
          direct_user_b?: string | null
          id?: string
          kind?: Database["public"]["Enums"]["thread_kind"]
          last_message_at?: string | null
          last_message_preview?: string | null
          title?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "message_threads_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_threads_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "analytics_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "message_threads_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_threads_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches_with_counts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_threads_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "mv_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "message_threads_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_threads_direct_user_a_fkey"
            columns: ["direct_user_a"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "message_threads_direct_user_b_fkey"
            columns: ["direct_user_b"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      messages: {
        Row: {
          academy_id: string
          attachments: Json
          content: string
          created_at: string
          deleted_at: string | null
          edited_at: string | null
          id: string
          sender_id: string
          thread_id: string
        }
        Insert: {
          academy_id: string
          attachments?: Json
          content: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          sender_id: string
          thread_id: string
        }
        Update: {
          academy_id?: string
          attachments?: Json
          content?: string
          created_at?: string
          deleted_at?: string | null
          edited_at?: string | null
          id?: string
          sender_id?: string
          thread_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_sender_id_fkey"
            columns: ["sender_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "messages_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "message_threads"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          academy_id: string | null
          category: Database["public"]["Enums"]["notification_category"]
          channel: Database["public"]["Enums"]["notification_channel"]
          enabled: boolean
          id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          academy_id?: string | null
          category: Database["public"]["Enums"]["notification_category"]
          channel: Database["public"]["Enums"]["notification_channel"]
          enabled?: boolean
          id?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          academy_id?: string | null
          category?: Database["public"]["Enums"]["notification_category"]
          channel?: Database["public"]["Enums"]["notification_channel"]
          enabled?: boolean
          id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_preferences_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          academy_id: string
          body: string | null
          category: Database["public"]["Enums"]["notification_category"]
          created_at: string
          deep_link: string | null
          entity_id: string | null
          entity_type: string | null
          id: string
          read_at: string | null
          title: string
          user_id: string
        }
        Insert: {
          academy_id: string
          body?: string | null
          category: Database["public"]["Enums"]["notification_category"]
          created_at?: string
          deep_link?: string | null
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          read_at?: string | null
          title: string
          user_id: string
        }
        Update: {
          academy_id?: string
          body?: string | null
          category?: Database["public"]["Enums"]["notification_category"]
          created_at?: string
          deep_link?: string | null
          entity_id?: string | null
          entity_type?: string | null
          id?: string
          read_at?: string | null
          title?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      parent_links: {
        Row: {
          academy_id: string
          created_at: string
          id: string
          is_primary: boolean
          parent_user_id: string
          relationship: string
          student_id: string
        }
        Insert: {
          academy_id: string
          created_at?: string
          id?: string
          is_primary?: boolean
          parent_user_id: string
          relationship?: string
          student_id: string
        }
        Update: {
          academy_id?: string
          created_at?: string
          id?: string
          is_primary?: boolean
          parent_user_id?: string
          relationship?: string
          student_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "parent_links_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "parent_links_parent_user_id_fkey"
            columns: ["parent_user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "parent_links_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "parent_links_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "parent_links_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_attempts: {
        Row: {
          academy_id: string
          amount: number
          attempt_number: number
          created_at: string
          failure_reason: string | null
          id: string
          invoice_id: string
          payment_id: string | null
          razorpay_order_id: string
          status: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          amount: number
          attempt_number?: number
          created_at?: string
          failure_reason?: string | null
          id?: string
          invoice_id: string
          payment_id?: string | null
          razorpay_order_id: string
          status?: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          amount?: number
          attempt_number?: number
          created_at?: string
          failure_reason?: string | null
          id?: string
          invoice_id?: string
          payment_id?: string | null
          razorpay_order_id?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_attempts_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_attempts_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payment_attempts_payment_id_fkey"
            columns: ["payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["id"]
          },
        ]
      }
      payments: {
        Row: {
          academy_id: string
          amount: number
          created_at: string
          id: string
          invoice_id: string
          method: string
          notes: string | null
          paid_at: string
          razorpay_order_id: string | null
          razorpay_payment_id: string | null
          razorpay_signature: string | null
          recorded_by: string | null
          status: string
          student_id: string
          unique_event_id: string | null
          updated_at: string
        }
        Insert: {
          academy_id: string
          amount: number
          created_at?: string
          id?: string
          invoice_id: string
          method: string
          notes?: string | null
          paid_at?: string
          razorpay_order_id?: string | null
          razorpay_payment_id?: string | null
          razorpay_signature?: string | null
          recorded_by?: string | null
          status?: string
          student_id: string
          unique_event_id?: string | null
          updated_at?: string
        }
        Update: {
          academy_id?: string
          amount?: number
          created_at?: string
          id?: string
          invoice_id?: string
          method?: string
          notes?: string | null
          paid_at?: string
          razorpay_order_id?: string | null
          razorpay_payment_id?: string | null
          razorpay_signature?: string | null
          recorded_by?: string | null
          status?: string
          student_id?: string
          unique_event_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "payments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "payments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      performance_assessments: {
        Row: {
          academy_id: string
          assessment_date: string
          batch_id: string | null
          coach_id: string | null
          created_at: string
          id: string
          overall_score: number | null
          qualitative_feedback: string | null
          recorded_by: string | null
          sport_id: string | null
          student_id: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          assessment_date?: string
          batch_id?: string | null
          coach_id?: string | null
          created_at?: string
          id?: string
          overall_score?: number | null
          qualitative_feedback?: string | null
          recorded_by?: string | null
          sport_id?: string | null
          student_id: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          assessment_date?: string
          batch_id?: string | null
          coach_id?: string | null
          created_at?: string
          id?: string
          overall_score?: number | null
          qualitative_feedback?: string | null
          recorded_by?: string | null
          sport_id?: string | null
          student_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "performance_assessments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_assessments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "analytics_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "performance_assessments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_assessments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "batches_with_counts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_assessments_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "mv_batch_utilization"
            referencedColumns: ["batch_id"]
          },
          {
            foreignKeyName: "performance_assessments_coach_id_fkey"
            columns: ["coach_id"]
            isOneToOne: false
            referencedRelation: "coaches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_assessments_recorded_by_fkey"
            columns: ["recorded_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_assessments_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_assessments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "performance_assessments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "performance_assessments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      performance_media: {
        Row: {
          academy_id: string
          assessment_id: string
          file_path: string
          id: string
          media_type: string
          mime_type: string | null
          original_filename: string | null
          size_bytes: number | null
          student_id: string
          uploaded_at: string
          uploaded_by: string | null
        }
        Insert: {
          academy_id: string
          assessment_id: string
          file_path: string
          id?: string
          media_type: string
          mime_type?: string | null
          original_filename?: string | null
          size_bytes?: number | null
          student_id: string
          uploaded_at?: string
          uploaded_by?: string | null
        }
        Update: {
          academy_id?: string
          assessment_id?: string
          file_path?: string
          id?: string
          media_type?: string
          mime_type?: string | null
          original_filename?: string | null
          size_bytes?: number | null
          student_id?: string
          uploaded_at?: string
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "performance_media_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_media_assessment_id_fkey"
            columns: ["assessment_id"]
            isOneToOne: false
            referencedRelation: "performance_assessments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_media_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "performance_media_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "performance_media_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_media_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      performance_skills: {
        Row: {
          academy_id: string
          assessment_id: string
          created_at: string
          id: string
          notes: string | null
          score: number
          skill_name: string
          student_id: string
        }
        Insert: {
          academy_id: string
          assessment_id: string
          created_at?: string
          id?: string
          notes?: string | null
          score: number
          skill_name: string
          student_id: string
        }
        Update: {
          academy_id?: string
          assessment_id?: string
          created_at?: string
          id?: string
          notes?: string | null
          score?: number
          skill_name?: string
          student_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "performance_skills_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_skills_assessment_id_fkey"
            columns: ["assessment_id"]
            isOneToOne: false
            referencedRelation: "performance_assessments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_skills_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "performance_skills_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "performance_skills_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      refunds: {
        Row: {
          academy_id: string
          amount: number
          approved_by: string | null
          created_at: string
          id: string
          payment_id: string
          processed_at: string | null
          razorpay_refund_id: string | null
          reason: string | null
          status: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          amount: number
          approved_by?: string | null
          created_at?: string
          id?: string
          payment_id: string
          processed_at?: string | null
          razorpay_refund_id?: string | null
          reason?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          amount?: number
          approved_by?: string | null
          created_at?: string
          id?: string
          payment_id?: string
          processed_at?: string | null
          razorpay_refund_id?: string | null
          reason?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "refunds_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "refunds_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "refunds_payment_id_fkey"
            columns: ["payment_id"]
            isOneToOne: false
            referencedRelation: "payments"
            referencedColumns: ["id"]
          },
        ]
      }
      saas_invoices: {
        Row: {
          academy_id: string
          amount: number
          amount_paid: number
          created_at: string
          currency: string
          due_date: string
          id: string
          invoice_number: string
          issued_at: string
          notes: string | null
          paid_at: string | null
          period_end: string
          period_start: string
          status: Database["public"]["Enums"]["saas_invoice_status"]
          subscription_id: string
          tax_amount: number
          total_amount: number | null
          updated_at: string
        }
        Insert: {
          academy_id: string
          amount: number
          amount_paid?: number
          created_at?: string
          currency?: string
          due_date: string
          id?: string
          invoice_number: string
          issued_at?: string
          notes?: string | null
          paid_at?: string | null
          period_end: string
          period_start: string
          status?: Database["public"]["Enums"]["saas_invoice_status"]
          subscription_id: string
          tax_amount?: number
          total_amount?: number | null
          updated_at?: string
        }
        Update: {
          academy_id?: string
          amount?: number
          amount_paid?: number
          created_at?: string
          currency?: string
          due_date?: string
          id?: string
          invoice_number?: string
          issued_at?: string
          notes?: string | null
          paid_at?: string | null
          period_end?: string
          period_start?: string
          status?: Database["public"]["Enums"]["saas_invoice_status"]
          subscription_id?: string
          tax_amount?: number
          total_amount?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "saas_invoices_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saas_invoices_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "academy_subscriptions"
            referencedColumns: ["id"]
          },
        ]
      }
      saas_payments: {
        Row: {
          academy_id: string
          amount: number
          created_at: string
          id: string
          method: Database["public"]["Enums"]["saas_payment_method"]
          notes: string | null
          paid_at: string
          razorpay_order_id: string | null
          razorpay_payment_id: string | null
          razorpay_signature: string | null
          reference: string | null
          saas_invoice_id: string
        }
        Insert: {
          academy_id: string
          amount: number
          created_at?: string
          id?: string
          method: Database["public"]["Enums"]["saas_payment_method"]
          notes?: string | null
          paid_at?: string
          razorpay_order_id?: string | null
          razorpay_payment_id?: string | null
          razorpay_signature?: string | null
          reference?: string | null
          saas_invoice_id: string
        }
        Update: {
          academy_id?: string
          amount?: number
          created_at?: string
          id?: string
          method?: Database["public"]["Enums"]["saas_payment_method"]
          notes?: string | null
          paid_at?: string
          razorpay_order_id?: string | null
          razorpay_payment_id?: string | null
          razorpay_signature?: string | null
          reference?: string | null
          saas_invoice_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "saas_payments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "saas_payments_saas_invoice_id_fkey"
            columns: ["saas_invoice_id"]
            isOneToOne: false
            referencedRelation: "saas_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      sport_skills: {
        Row: {
          created_at: string
          id: string
          name: string
          sort_order: number
          sport_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          sort_order?: number
          sport_id: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          sort_order?: number
          sport_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "sport_skills_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      sports: {
        Row: {
          category: string | null
          code: string
          created_at: string
          id: string
          is_active: boolean
          name: string
        }
        Insert: {
          category?: string | null
          code: string
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
        }
        Update: {
          category?: string | null
          code?: string
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
        }
        Relationships: []
      }
      student_discount_assignments: {
        Row: {
          academy_id: string
          created_at: string
          discount_structure_id: string
          end_date: string | null
          id: string
          is_active: boolean
          stack_with_batch: boolean
          start_date: string
          student_id: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          created_at?: string
          discount_structure_id: string
          end_date?: string | null
          id?: string
          is_active?: boolean
          stack_with_batch?: boolean
          start_date?: string
          student_id: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          created_at?: string
          discount_structure_id?: string
          end_date?: string | null
          id?: string
          is_active?: boolean
          stack_with_batch?: boolean
          start_date?: string
          student_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_discount_assignments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_discount_assignments_discount_structure_id_fkey"
            columns: ["discount_structure_id"]
            isOneToOne: false
            referencedRelation: "discount_structures"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_discount_assignments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "student_discount_assignments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "student_discount_assignments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      student_documents: {
        Row: {
          academy_id: string
          file_path: string
          id: string
          mime_type: string | null
          original_filename: string | null
          size_bytes: number | null
          student_id: string
          type: string
          uploaded_at: string
          uploaded_by: string | null
        }
        Insert: {
          academy_id: string
          file_path: string
          id?: string
          mime_type?: string | null
          original_filename?: string | null
          size_bytes?: number | null
          student_id: string
          type: string
          uploaded_at?: string
          uploaded_by?: string | null
        }
        Update: {
          academy_id?: string
          file_path?: string
          id?: string
          mime_type?: string | null
          original_filename?: string | null
          size_bytes?: number | null
          student_id?: string
          type?: string
          uploaded_at?: string
          uploaded_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "student_documents_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_documents_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "student_documents_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "student_documents_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_documents_uploaded_by_fkey"
            columns: ["uploaded_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      student_fee_assignments: {
        Row: {
          academy_id: string
          billing_day: number | null
          created_at: string
          end_date: string | null
          fee_structure_id: string
          id: string
          is_active: boolean
          start_date: string
          student_id: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          billing_day?: number | null
          created_at?: string
          end_date?: string | null
          fee_structure_id: string
          id?: string
          is_active?: boolean
          start_date?: string
          student_id: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          billing_day?: number | null
          created_at?: string
          end_date?: string | null
          fee_structure_id?: string
          id?: string
          is_active?: boolean
          start_date?: string
          student_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_fee_assignments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_fee_assignments_fee_structure_id_fkey"
            columns: ["fee_structure_id"]
            isOneToOne: false
            referencedRelation: "fee_structures"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_fee_assignments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "student_fee_assignments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "student_fee_assignments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      students: {
        Row: {
          academy_id: string
          address: string | null
          center_id: string | null
          city: string | null
          created_at: string
          date_of_birth: string | null
          email: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          enrollment_date: string
          first_name: string
          gender: string | null
          id: string
          injury_info: string | null
          is_active: boolean
          last_name: string
          medical_notes: string | null
          parent_alternate_phone: string | null
          parent_email: string | null
          parent_name: string
          parent_phone: string | null
          phone: string | null
          photo: string | null
          pincode: string | null
          skill_level: string | null
          sport_id: string | null
          state: string | null
          status: string
          updated_at: string
          user_id: string | null
        }
        Insert: {
          academy_id: string
          address?: string | null
          center_id?: string | null
          city?: string | null
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          enrollment_date?: string
          first_name: string
          gender?: string | null
          id?: string
          injury_info?: string | null
          is_active?: boolean
          last_name: string
          medical_notes?: string | null
          parent_alternate_phone?: string | null
          parent_email?: string | null
          parent_name: string
          parent_phone?: string | null
          phone?: string | null
          photo?: string | null
          pincode?: string | null
          skill_level?: string | null
          sport_id?: string | null
          state?: string | null
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Update: {
          academy_id?: string
          address?: string | null
          center_id?: string | null
          city?: string | null
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          enrollment_date?: string
          first_name?: string
          gender?: string | null
          id?: string
          injury_info?: string | null
          is_active?: boolean
          last_name?: string
          medical_notes?: string | null
          parent_alternate_phone?: string | null
          parent_email?: string | null
          parent_name?: string
          parent_phone?: string | null
          phone?: string | null
          photo?: string | null
          pincode?: string | null
          skill_level?: string | null
          sport_id?: string | null
          state?: string | null
          status?: string
          updated_at?: string
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "students_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "students_center_id_fkey"
            columns: ["center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "students_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "students_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_plans: {
        Row: {
          code: string
          created_at: string
          currency: string
          description: string | null
          features: Json
          id: string
          is_active: boolean
          max_centers: number | null
          max_coaches: number | null
          max_students: number | null
          monthly_price: number
          name: string
          updated_at: string
          yearly_price: number | null
        }
        Insert: {
          code: string
          created_at?: string
          currency?: string
          description?: string | null
          features?: Json
          id?: string
          is_active?: boolean
          max_centers?: number | null
          max_coaches?: number | null
          max_students?: number | null
          monthly_price: number
          name: string
          updated_at?: string
          yearly_price?: number | null
        }
        Update: {
          code?: string
          created_at?: string
          currency?: string
          description?: string | null
          features?: Json
          id?: string
          is_active?: boolean
          max_centers?: number | null
          max_coaches?: number | null
          max_students?: number | null
          monthly_price?: number
          name?: string
          updated_at?: string
          yearly_price?: number | null
        }
        Relationships: []
      }
      support_ticket_messages: {
        Row: {
          academy_id: string
          author_id: string | null
          body: string
          created_at: string
          id: string
          is_staff: boolean
          ticket_id: string
        }
        Insert: {
          academy_id: string
          author_id?: string | null
          body: string
          created_at?: string
          id?: string
          is_staff?: boolean
          ticket_id: string
        }
        Update: {
          academy_id?: string
          author_id?: string | null
          body?: string
          created_at?: string
          id?: string
          is_staff?: boolean
          ticket_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "support_ticket_messages_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "support_ticket_messages_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "support_ticket_messages_ticket_id_fkey"
            columns: ["ticket_id"]
            isOneToOne: false
            referencedRelation: "support_tickets"
            referencedColumns: ["id"]
          },
        ]
      }
      support_tickets: {
        Row: {
          academy_id: string
          assigned_to: string | null
          body: string
          category: string | null
          closed_at: string | null
          created_at: string
          id: string
          opened_by: string | null
          priority: string
          resolved_at: string | null
          status: Database["public"]["Enums"]["support_ticket_status"]
          subject: string
          updated_at: string
        }
        Insert: {
          academy_id: string
          assigned_to?: string | null
          body: string
          category?: string | null
          closed_at?: string | null
          created_at?: string
          id?: string
          opened_by?: string | null
          priority?: string
          resolved_at?: string | null
          status?: Database["public"]["Enums"]["support_ticket_status"]
          subject: string
          updated_at?: string
        }
        Update: {
          academy_id?: string
          assigned_to?: string | null
          body?: string
          category?: string | null
          closed_at?: string | null
          created_at?: string
          id?: string
          opened_by?: string | null
          priority?: string
          resolved_at?: string | null
          status?: Database["public"]["Enums"]["support_ticket_status"]
          subject?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "support_tickets_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "support_tickets_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "support_tickets_opened_by_fkey"
            columns: ["opened_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      thread_participants: {
        Row: {
          academy_id: string
          is_muted: boolean
          joined_at: string
          last_read_at: string | null
          thread_id: string
          user_id: string
        }
        Insert: {
          academy_id: string
          is_muted?: boolean
          joined_at?: string
          last_read_at?: string | null
          thread_id: string
          user_id: string
        }
        Update: {
          academy_id?: string
          is_muted?: boolean
          joined_at?: string
          last_read_at?: string | null
          thread_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "thread_participants_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "thread_participants_thread_id_fkey"
            columns: ["thread_id"]
            isOneToOne: false
            referencedRelation: "message_threads"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "thread_participants_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      users: {
        Row: {
          academy_id: string | null
          center_id: string | null
          created_at: string
          email: string | null
          first_name: string | null
          id: string
          is_active: boolean
          last_login: string | null
          last_name: string | null
          must_change_password: boolean
          phone: string | null
          preferences: Json
          profile_photo: string | null
          role: Database["public"]["Enums"]["user_role"]
          updated_at: string
        }
        Insert: {
          academy_id?: string | null
          center_id?: string | null
          created_at?: string
          email?: string | null
          first_name?: string | null
          id: string
          is_active?: boolean
          last_login?: string | null
          last_name?: string | null
          must_change_password?: boolean
          phone?: string | null
          preferences?: Json
          profile_photo?: string | null
          role: Database["public"]["Enums"]["user_role"]
          updated_at?: string
        }
        Update: {
          academy_id?: string | null
          center_id?: string | null
          created_at?: string
          email?: string | null
          first_name?: string | null
          id?: string
          is_active?: boolean
          last_login?: string | null
          last_name?: string | null
          must_change_password?: boolean
          phone?: string | null
          preferences?: Json
          profile_photo?: string | null
          role?: Database["public"]["Enums"]["user_role"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "users_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "users_center_id_fkey"
            columns: ["center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
        ]
      }
      vendors: {
        Row: {
          academy_id: string
          address: string | null
          contact_name: string | null
          created_at: string
          email: string | null
          id: string
          is_active: boolean
          name: string
          notes: string | null
          phone: string | null
          updated_at: string
        }
        Insert: {
          academy_id: string
          address?: string | null
          contact_name?: string | null
          created_at?: string
          email?: string | null
          id?: string
          is_active?: boolean
          name: string
          notes?: string | null
          phone?: string | null
          updated_at?: string
        }
        Update: {
          academy_id?: string
          address?: string | null
          contact_name?: string | null
          created_at?: string
          email?: string | null
          id?: string
          is_active?: boolean
          name?: string
          notes?: string | null
          phone?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "vendors_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      analytics_batch_utilization: {
        Row: {
          academy_id: string | null
          batch_id: string | null
          capacity: number | null
          enrolled: number | null
          name: string | null
        }
        Relationships: [
          {
            foreignKeyName: "batches_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      analytics_collection_summary: {
        Row: {
          academy_id: string | null
          collected_total: number | null
          outstanding_amount: number | null
          outstanding_count: number | null
          overdue_count: number | null
          paid_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "invoices_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      analytics_enrollment_by_month: {
        Row: {
          academy_id: string | null
          enrollment_count: number | null
          month_start: string | null
        }
        Relationships: [
          {
            foreignKeyName: "batch_enrollments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      analytics_lead_funnel_summary: {
        Row: {
          academy_id: string | null
          cnt: number | null
          source: Database["public"]["Enums"]["lead_source"] | null
          status: Database["public"]["Enums"]["lead_status"] | null
        }
        Relationships: [
          {
            foreignKeyName: "leads_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      analytics_revenue_by_month: {
        Row: {
          academy_id: string | null
          billed: number | null
          collected: number | null
          invoice_count: number | null
          month_start: string | null
          outstanding: number | null
          paid_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "invoices_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      batches_with_counts: {
        Row: {
          academy_id: string | null
          age_group: string | null
          capacity: number | null
          center_id: string | null
          coach_id: string | null
          created_at: string | null
          description: string | null
          end_date: string | null
          enrolled_count: number | null
          id: string | null
          is_active: boolean | null
          name: string | null
          schedule: Json | null
          skill_level: string | null
          sport_id: string | null
          start_date: string | null
          updated_at: string | null
        }
        Relationships: [
          {
            foreignKeyName: "batches_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batches_center_id_fkey"
            columns: ["center_id"]
            isOneToOne: false
            referencedRelation: "centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batches_coach_id_fkey"
            columns: ["coach_id"]
            isOneToOne: false
            referencedRelation: "coaches"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "batches_sport_id_fkey"
            columns: ["sport_id"]
            isOneToOne: false
            referencedRelation: "sports"
            referencedColumns: ["id"]
          },
        ]
      }
      mv_batch_utilization: {
        Row: {
          academy_id: string | null
          batch_id: string | null
          capacity: number | null
          enrolled: number | null
          name: string | null
        }
        Relationships: [
          {
            foreignKeyName: "batches_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      mv_collection_summary: {
        Row: {
          academy_id: string | null
          collected_total: number | null
          outstanding_amount: number | null
          outstanding_count: number | null
          overdue_count: number | null
          paid_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "invoices_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      mv_enrollment_by_month: {
        Row: {
          academy_id: string | null
          enrollment_count: number | null
          month_start: string | null
        }
        Relationships: [
          {
            foreignKeyName: "batch_enrollments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      mv_lead_funnel_summary: {
        Row: {
          academy_id: string | null
          cnt: number | null
          source: Database["public"]["Enums"]["lead_source"] | null
          status: Database["public"]["Enums"]["lead_status"] | null
        }
        Relationships: [
          {
            foreignKeyName: "leads_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      mv_revenue_by_month: {
        Row: {
          academy_id: string | null
          billed: number | null
          collected: number | null
          invoice_count: number | null
          month_start: string | null
          outstanding: number | null
          paid_count: number | null
        }
        Relationships: [
          {
            foreignKeyName: "invoices_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      student_attendance_summary: {
        Row: {
          absent_count: number | null
          academy_id: string | null
          attendance_pct: number | null
          excused_count: number | null
          last_attended_date: string | null
          late_count: number | null
          present_count: number | null
          refreshed_at: string | null
          student_id: string | null
          total_sessions: number | null
        }
        Relationships: [
          {
            foreignKeyName: "students_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      student_attendance_summary_view: {
        Row: {
          absent_count: number | null
          academy_id: string | null
          attendance_pct: number | null
          excused_count: number | null
          last_attended_date: string | null
          late_count: number | null
          present_count: number | null
          refreshed_at: string | null
          student_id: string | null
          total_sessions: number | null
        }
        Relationships: [
          {
            foreignKeyName: "students_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
        ]
      }
      student_performance_trend: {
        Row: {
          academy_id: string | null
          avg_recent_score: number | null
          last_assessed_date: string | null
          latest_sport_id: string | null
          recent_assessments: number | null
          refreshed_at: string | null
          student_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "performance_assessments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_assessments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "performance_assessments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "performance_assessments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
      student_performance_trend_view: {
        Row: {
          academy_id: string | null
          avg_recent_score: number | null
          last_assessed_date: string | null
          latest_sport_id: string | null
          recent_assessments: number | null
          refreshed_at: string | null
          student_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "performance_assessments_academy_id_fkey"
            columns: ["academy_id"]
            isOneToOne: false
            referencedRelation: "academies"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "performance_assessments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "performance_assessments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "student_attendance_summary_view"
            referencedColumns: ["student_id"]
          },
          {
            foreignKeyName: "performance_assessments_student_id_fkey"
            columns: ["student_id"]
            isOneToOne: false
            referencedRelation: "students"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      batch_in_my_center: { Args: { p_batch_id: string }; Returns: boolean }
      bootstrap_owner_academy: {
        Args: { p_academy_name: string }
        Returns: {
          address: string | null
          city: string | null
          created_at: string
          email: string | null
          holidays: string[]
          hours_close: string | null
          hours_open: string | null
          id: string
          invoice_prefix: string
          is_active: boolean
          logo: string | null
          name: string
          owner_id: string | null
          phone: string | null
          pincode: string | null
          settings: Json
          state: string | null
          subscription_status: Database["public"]["Enums"]["subscription_status"]
          trial_ends_at: string | null
          updated_at: string
          website: string | null
        }
        SetofOptions: {
          from: "*"
          to: "academies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      can_admin_center_scope: {
        Args: { p_center_id: string }
        Returns: boolean
      }
      can_admin_lead: { Args: { p_lead_id: string }; Returns: boolean }
      can_manage_batches: { Args: { p_center_id: string }; Returns: boolean }
      can_manage_enrollment: { Args: { p_batch_id: string }; Returns: boolean }
      can_mark_attendance: { Args: { p_batch_id: string }; Returns: boolean }
      can_record_perf_for_assessment: {
        Args: { p_assessment_id: string }
        Returns: boolean
      }
      can_record_performance: { Args: { p_batch_id: string }; Returns: boolean }
      center_admin_sees_batch: {
        Args: { p_batch_id: string }
        Returns: boolean
      }
      center_admin_sees_center: {
        Args: { p_center_id: string }
        Returns: boolean
      }
      center_admin_sees_student: {
        Args: { p_student_id: string }
        Returns: boolean
      }
      coach_owns_batch: { Args: { p_batch_id: string }; Returns: boolean }
      convert_lead: {
        Args: {
          p_batch_id?: string
          p_lead_id: string
          p_parent_user_id?: string
          p_start_date?: string
        }
        Returns: string
      }
      cron_invoke_function: { Args: { p_path: string }; Returns: undefined }
      current_user_academy_id: { Args: never; Returns: string }
      current_user_center_id: { Args: never; Returns: string }
      current_user_role: {
        Args: never
        Returns: Database["public"]["Enums"]["user_role"]
      }
      ensure_batch_thread: { Args: { p_batch_id: string }; Returns: string }
      ensure_direct_thread: {
        Args: { p_other_user_id: string }
        Returns: string
      }
      has_admin_or_higher: { Args: never; Returns: boolean }
      has_coach_or_higher: { Args: never; Returns: boolean }
      has_role: {
        Args: { check_role: Database["public"]["Enums"]["user_role"] }
        Returns: boolean
      }
      is_super_admin: { Args: never; Returns: boolean }
      is_thread_participant: { Args: { p_thread_id: string }; Returns: boolean }
      mark_all_notifications_read: { Args: never; Returns: number }
      mark_announcement_read: {
        Args: { p_announcement_id: string }
        Returns: undefined
      }
      mark_notification_read: { Args: { p_id: string }; Returns: undefined }
      mark_thread_read: { Args: { p_thread_id: string }; Returns: undefined }
      my_linked_student_ids: { Args: never; Returns: string[] }
      next_invoice_number: { Args: { p_academy_id: string }; Returns: string }
      parent_can_see_student: {
        Args: { p_student_id: string }
        Returns: boolean
      }
      refresh_analytics: { Args: never; Returns: undefined }
      refresh_attendance_aggregates: { Args: never; Returns: undefined }
      register_device_token: {
        Args: {
          p_app_version?: string
          p_device_id?: string
          p_platform: string
          p_token: string
        }
        Returns: undefined
      }
      reschedule_cron: {
        Args: { p_command: string; p_jobname: string; p_schedule: string }
        Returns: undefined
      }
      transfer_enrollment: {
        Args: { p_enrollment_id: string; p_target_batch_id: string }
        Returns: {
          academy_id: string
          batch_id: string
          enrolled_at: string
          enrollment_status: string
          id: string
          student_id: string
        }
        SetofOptions: {
          from: "*"
          to: "batch_enrollments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      unread_notification_count: { Args: never; Returns: number }
    }
    Enums: {
      event_kind: "tournament" | "workshop" | "camp" | "fixture" | "social"
      event_status:
        | "draft"
        | "published"
        | "registration_closed"
        | "in_progress"
        | "completed"
        | "cancelled"
      lead_source:
        | "website"
        | "referral"
        | "walk_in"
        | "instagram"
        | "facebook"
        | "google"
        | "event"
        | "other"
      lead_status:
        | "new"
        | "contacted"
        | "interested"
        | "trial_scheduled"
        | "converted"
        | "lost"
      notification_category:
        | "announcement"
        | "message"
        | "attendance"
        | "performance"
        | "invoice"
        | "payment"
        | "lead"
        | "system"
      notification_channel: "push" | "email" | "in_app"
      saas_invoice_status: "issued" | "paid" | "past_due" | "cancelled"
      saas_payment_method: "razorpay" | "bank_transfer" | "manual" | "free"
      subscription_status:
        | "trial"
        | "active"
        | "past_due"
        | "suspended"
        | "cancelled"
      support_ticket_status:
        | "open"
        | "in_progress"
        | "waiting_on_user"
        | "resolved"
        | "closed"
      thread_kind: "direct" | "batch"
      user_role:
        | "super_admin"
        | "academy_owner"
        | "academy_admin"
        | "center_admin"
        | "head_coach"
        | "coach"
        | "trainer"
        | "parent"
        | "student"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      event_kind: ["tournament", "workshop", "camp", "fixture", "social"],
      event_status: [
        "draft",
        "published",
        "registration_closed",
        "in_progress",
        "completed",
        "cancelled",
      ],
      lead_source: [
        "website",
        "referral",
        "walk_in",
        "instagram",
        "facebook",
        "google",
        "event",
        "other",
      ],
      lead_status: [
        "new",
        "contacted",
        "interested",
        "trial_scheduled",
        "converted",
        "lost",
      ],
      notification_category: [
        "announcement",
        "message",
        "attendance",
        "performance",
        "invoice",
        "payment",
        "lead",
        "system",
      ],
      notification_channel: ["push", "email", "in_app"],
      saas_invoice_status: ["issued", "paid", "past_due", "cancelled"],
      saas_payment_method: ["razorpay", "bank_transfer", "manual", "free"],
      subscription_status: [
        "trial",
        "active",
        "past_due",
        "suspended",
        "cancelled",
      ],
      support_ticket_status: [
        "open",
        "in_progress",
        "waiting_on_user",
        "resolved",
        "closed",
      ],
      thread_kind: ["direct", "batch"],
      user_role: [
        "super_admin",
        "academy_owner",
        "academy_admin",
        "center_admin",
        "head_coach",
        "coach",
        "trainer",
        "parent",
        "student",
      ],
    },
  },
} as const


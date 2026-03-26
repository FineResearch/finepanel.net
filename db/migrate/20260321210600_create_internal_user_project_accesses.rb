class CreateInternalUserProjectAccesses < ActiveRecord::Migration[5.2]
  def change
    create_table :internal_user_project_accesses do |t|
      t.references :internal_user, null: false, foreign_key: true
      t.string :project_code, null: false

      t.timestamps
    end

    add_index :internal_user_project_accesses,
              [:internal_user_id, :project_code],
              unique: true,
              name: 'idx_internal_user_project_access_unique'
    add_index :internal_user_project_accesses, :project_code
  end
end

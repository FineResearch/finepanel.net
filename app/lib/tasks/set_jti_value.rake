task set_jti_value: :environment do
  User.find_each do |user|
    user.update_column(:jti, SecureRandom.uuid)
  end
end

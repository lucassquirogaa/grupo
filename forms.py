from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, BooleanField, SelectField, TextAreaField
from wtforms.validators import DataRequired, Length, Email, Optional

class EditUserForm(FlaskForm):
    username = StringField('Usuario', validators=[DataRequired(), Length(min=3, max=80)])
    full_name = StringField('Nombre Completo', validators=[Length(max=120)])
    email = StringField('Email', validators=[Email(), Length(max=120)])
    role = SelectField('Rol', choices=[('user', 'Usuario'), ('admin', 'Administrador')])
    is_active = BooleanField('Cuenta Activa')
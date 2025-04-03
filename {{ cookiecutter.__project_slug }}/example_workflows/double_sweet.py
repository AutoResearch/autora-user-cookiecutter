"""
Basic Workflow
    Single condition Variable (0-1), Single Observation Variable(0-1)
    Theorist: LinearRegression
    Experimentalist: Random Sampling
    Runner: Firebase Runner (no prolific recruitment)
"""

import json

from autora.variable import VariableCollection, Variable
from autora.experimentalist.random import pool
from autora.experiment_runner.firebase_prolific import firebase_runner
from autora.state import StandardState, on_state, Delta

import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression
import sweetbean as sb
import sweetbean.stimulus as sb_s
import sweetbean.variable as sb_v

import sweetpea as sp

# *** Set up variables *** #
# independent variable is coherence in percent (0 - 100)
# dependent variable is rt in ms (0 - 10000)
variables = VariableCollection(
    independent_variables=[Variable(name="number", allowed_values=np.linspace(0, 40, 41))],
    dependent_variables=[Variable(name="rt", value_range=(0, 10000))],)

# *** State *** #
# With the variables, we can set up a state. The state object represents the state of our
# closed loop experiment.


state = StandardState(
    variables=variables,
)

# *** Components/Agents *** #
# Components are functions that run on the state. The main components are:
# - theorist
# - experiment-runner
# - experimentalist
# See more about components here: https://autoresearch.github.io/autora/


# ** Theorist ** #
# Here we use a linear regression as theorist, but you can use other theorists included in
# autora (for a list: https://autoresearch.github.io/autora/theorist/)

theorist = LinearRegression()


# To use the theorist on the state object, we wrap it with the on_state functionality and return a
# Delta object.
# Note: The if the input arguments of the theorist_on_state function are state-fields like
# experiment_data, variables, ... , then using this function on a state object will automatically
# use those state fields.
# The output of these functions is always a Delta object. The keyword argument in this case, tells
# the state object witch field to update.


@on_state()
def theorist_on_state(experiment_data, variables):
    ivs = [iv.name for iv in variables.independent_variables]
    dvs = [dv.name for dv in variables.dependent_variables]
    x = experiment_data[ivs]
    y = experiment_data[dvs]
    return Delta(models=[theorist.fit(x, y)])


# ** Experimentalist ** #
# Here, we use a random pool and use the wrapper to create a on state function
# Note: The argument num_samples is not a state field. Instead, we will pass it in when calling
# the function


@on_state()
def experimentalist_on_state(variables, num_samples):
    return Delta(conditions=pool(variables, num_samples))


# ** Experiment Runner ** #
# We will run our experiment on firebase and need credentials. You will find them here:
# (https://console.firebase.google.com/)
#   -> project -> project settings -> service accounts -> generate new private key

firebase_credentials = {
  "type": "type",
  "project_id": "project_id-tst",
  "private_key_id": "private_key_id",
  "private_key": "private_key",
  "client_email": "client_email",
  "client_id": "client_id",
  "auth_uri": "auth_uri",
  "token_uri": "token_uri",
  "auth_provider_x509_cert_url": "auth_provider_x509_cert_url",
  "client_x509_cert_url": "client_x509_cert_url",
  "universe_domain": "universe_domain"
}


# simple experiment runner that runs the experiment on firebase
experiment_runner = firebase_runner(
    firebase_credentials=firebase_credentials,
    time_out=100,
    sleep_time=5)


# Again, we need to wrap the runner to use it on the state. Here, we send the raw conditions.
@on_state()
def runner_on_state(conditions):
    # Here, we convert conditions into sweet bean code to send the complete experiment code
    # directly to the server
    numbers = list(conditions['number'])
    res = []
    for number in numbers:
        # we use sweetbean to create a full experiment from the numbers

        # For more information on sweetbean: https://autoresearch.github.io/sweetbean/
        text = sb_s.Text(
            duration=10000, text=f"press a if {number} is larger then 20, b if not.",
            color="purple", choices=["a", "b"]
        )
        block = sb.Block([text])
        experiment = sb.Experiment([block])
        # here we export the experiment as javascript function
        condition = experiment.to_js_string(as_function=True, is_async=True)
        res.append(condition)
    # We append a column (experiment_code) to the conditions and send it to the runner
    conditions_to_send = conditions.copy()
    conditions_to_send['experiment_code'] = res
    data = experiment_runner(conditions_to_send)
    # Here, parse the return value of the runner. The return value depends on the specific
    # implementation of your online experiment (see testing_zone/src/design/main.js).
    # In this example, the experiment runner returns a list of strings, that contain json formatted
    # dictionaries.
    # Example:
    # data = ['{'number':4, rt':.8}', ...]
    result = []
    for item in data:
        result.append(json.loads(item))
    return Delta(experiment_data=pd.DataFrame(result))


# Now, we can run our components
for _ in range(3):
    state = experimentalist_on_state(state, num_samples=2)  # Collect 2 conditions per iteration
    state = runner_on_state(state)
    state = theorist_on_state(state)


# *** Report the data *** #
# If you changed the theorist, also change this part
def report_linear_fit(m: LinearRegression, precision=4):
    s = f"y = {np.round(m.coef_[0].item(), precision)} x " \
        f"+ {np.round(m.intercept_.item(), 4)}"
    return s


print(report_linear_fit(state.models[0]))
print(report_linear_fit(state.models[-1]))
